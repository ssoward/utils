import Foundation
import AppKit

enum OutlookCalendarFetcher {

    // Iterates every calendar in Outlook, filters in AppleScript to the next
    // 24h, and emits one record per event:
    //
    //   subject \t startISO \t endISO \t location \n
    //
    // Diagnostic lines may precede or follow:
    //   "::CALENDARS::<count>"
    //   "::ERR::<message>"     (one per failing calendar)
    //   "::OUTER::<message>"   (outer try failure)
    //
    // No `¬` line continuations and verbose variable names — short names like
    // `st` collided with Outlook's compiler in some builds, returning errno
    // -2741.
    private static let script = #"""
    on padTwo(n)
        set s to (n as integer) as string
        if (count of s) is 1 then set s to "0" & s
        return s
    end padTwo

    on isoFromDate(theDate)
        set y to (year of theDate) as string
        set m to my padTwo(month of theDate)
        set d to my padTwo(day of theDate)
        set h to my padTwo(hours of theDate)
        set mi to my padTwo(minutes of theDate)
        set se to my padTwo(seconds of theDate)
        return y & "-" & m & "-" & d & "T" & h & ":" & mi & ":" & se
    end isoFromDate

    tell application "Microsoft Outlook"
        set output to ""
        try
            set theCalendars to every calendar
            set output to output & "::CALENDARS::" & (count of theCalendars as string) & linefeed
            set nowDate to (current date)
            set windowEnd to nowDate + (24 * hours)
            repeat with theCalendar in theCalendars
                try
                    set theEvents to (every calendar event of theCalendar whose start time ≥ nowDate and start time ≤ windowEnd)
                    repeat with theEvent in theEvents
                        try
                            set evtSubject to (subject of theEvent) as string
                            set evtStart to start time of theEvent
                            set evtEnd to end time of theEvent
                            set evtLocation to ""
                            try
                                set evtLocation to (location of theEvent) as string
                            end try
                            set startISO to my isoFromDate(evtStart)
                            set endISO to my isoFromDate(evtEnd)
                            set output to output & evtSubject & tab & startISO & tab & endISO & tab & evtLocation & linefeed
                        end try
                    end repeat
                on error innerErr
                    set output to output & "::ERR::" & innerErr & linefeed
                end try
            end repeat
        on error outerErr
            set output to output & "::OUTER::" & outerErr & linefeed
        end try
        return output
    end tell
    """#

    static func fetchUpcoming() async -> SectionResult {
        await Task.detached(priority: .userInitiated) { run() }.value
    }

    private static func run() -> SectionResult {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.Outlook") != nil else {
            return SectionResult(items: [], status: "Microsoft Outlook is not installed.")
        }

        var error: NSDictionary?
        guard let apple = NSAppleScript(source: script) else {
            return SectionResult(items: [], status: "Internal: couldn't compile Outlook calendar script.")
        }

        let result = apple.executeAndReturnError(&error)
        if let err = error {
            return SectionResult(items: [], status: "Outlook calendar (AppleScript failed): \(formatError(err))")
        }

        let text = result.stringValue ?? ""
        let parsed = parse(text)

        if !parsed.items.isEmpty {
            return SectionResult(items: parsed.items, status: parsed.diagnostic)
        }

        // No items — surface diagnostic so the user can see what happened.
        let suffix = " (If you're on the New Outlook, switch back to legacy: Outlook menu → New Outlook → off. Otherwise: System Settings → Privacy & Security → Automation → BrotherPaul → enable Microsoft Outlook.)"
        if let d = parsed.diagnostic {
            return SectionResult(items: [], status: "Outlook calendar: \(d).\(parsed.hasError ? suffix : "")")
        }
        return SectionResult(items: [], status: "Outlook calendar: no events in the next 24h.")
    }

    // MARK: - Output parsing

    private struct ParseResult {
        var items: [DigestItem]
        var diagnostic: String?
        var hasError: Bool
    }

    private static func parse(_ text: String) -> ParseResult {
        let lines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init)

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"

        var items: [DigestItem] = []
        var calendars: Int = -1
        var innerErrors: [String] = []
        var outerError: String?

        for line in lines {
            if line.hasPrefix("::CALENDARS::") {
                calendars = Int(line.dropFirst("::CALENDARS::".count)) ?? -1
            } else if line.hasPrefix("::ERR::") {
                innerErrors.append(String(line.dropFirst("::ERR::".count)))
            } else if line.hasPrefix("::OUTER::") {
                outerError = String(line.dropFirst("::OUTER::".count))
            } else {
                let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
                guard parts.count >= 3 else { continue }
                let subject = String(parts[0])
                guard let start = dateFormatter.date(from: String(parts[1])) else { continue }
                let end = dateFormatter.date(from: String(parts[2]))
                let location = parts.count > 3 ? String(parts[3]) : ""

                let timeStr: String = {
                    let s = timeFormatter.string(from: start)
                    let when = end.map { "\(s) – \(timeFormatter.string(from: $0))" } ?? s
                    return Calendar.current.isDateInToday(start) ? when : "\(dayFormatter.string(from: start)) \(when)"
                }()
                let subtitle = location.isEmpty ? timeStr : "\(timeStr)  ·  \(location)"

                let minutesAway = Int(start.timeIntervalSinceNow / 60)
                let priority: Int = {
                    if minutesAway <= 15 { return 100 }
                    if minutesAway <= 60 { return 80 }
                    return 60
                }()

                items.append(DigestItem(
                    source: .calendar,
                    title: subject.isEmpty ? "(no subject)" : subject,
                    subtitle: subtitle,
                    timestamp: start,
                    priority: priority,
                    openURL: nil
                ))
            }
        }

        var diagBits: [String] = []
        if calendars >= 0 { diagBits.append("Outlook reports \(calendars) calendar(s)") }
        if let o = outerError { diagBits.append("outer error: \(o)") }
        if !innerErrors.isEmpty { diagBits.append("per-calendar errors: \(innerErrors.joined(separator: "; "))") }

        return ParseResult(
            items: items,
            diagnostic: diagBits.isEmpty ? nil : diagBits.joined(separator: "  •  "),
            hasError: outerError != nil || !innerErrors.isEmpty
        )
    }

    private static func formatError(_ err: NSDictionary) -> String {
        let num = err[NSAppleScript.errorNumber] as? Int
        let msg = (err[NSAppleScript.errorMessage] as? String) ?? "(no message)"
        let brief = err[NSAppleScript.errorBriefMessage] as? String
        let app = err[NSAppleScript.errorAppName] as? String

        var pieces = [msg]
        if let b = brief, b != msg { pieces.append("[\(b)]") }
        if let a = app { pieces.append("from \(a)") }
        let numSuffix = num.map { " (errno \($0))" } ?? ""
        let base = pieces.joined(separator: " ") + numSuffix

        switch num {
        case -1751, -1728, -10000, -1708:
            return base + " — Outlook doesn't recognize the 'calendar event' class. You're almost certainly on the New Outlook, which strips most of the AppleScript dictionary. Fix: top menu → Outlook → New Outlook → toggle off (Legacy). If your Microsoft 365 install no longer offers a Legacy toggle, the AppleScript path can't reach the calendar — we'd need a Microsoft Graph integration instead."
        case -1743:
            return base + " — Automation permission denied. Grant it in System Settings → Privacy & Security → Automation → BrotherPaul → Microsoft Outlook."
        case -600:
            return base + " — Microsoft Outlook isn't running."
        default:
            return base
        }
    }
}
