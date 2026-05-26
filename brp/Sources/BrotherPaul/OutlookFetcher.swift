import Foundation
import AppKit

enum OutlookFetcher {

    // Records: subject \t sender \t timeReceived (one record per line, fields tab-separated).
    private static let script = """
    tell application "Microsoft Outlook"
        set output to ""
        try
            set msgs to (messages of inbox whose is read is false)
            set cutoff to (current date) - (24 * hours)
            repeat with m in msgs
                try
                    set t to time received of m
                    if t > cutoff then
                        set subj to (subject of m as string)
                        set senderName to ""
                        try
                            set senderName to (name of sender of m as string)
                        end try
                        if senderName is "" then
                            try
                                set senderName to (address of sender of m as string)
                            end try
                        end if
                        set output to output & subj & tab & senderName & tab & ((t as «class isot» as string)) & linefeed
                    end if
                end try
            end repeat
        end try
        return output
    end tell
    """

    static func fetchUnread(vipSenders: [String]) async -> SectionResult {
        await Task.detached(priority: .userInitiated) { runScript(vipSenders: vipSenders) }.value
    }

    private static func runScript(vipSenders: [String]) -> SectionResult {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.Outlook") != nil else {
            return SectionResult(items: [], status: "Microsoft Outlook is not installed.")
        }

        var error: NSDictionary?
        guard let apple = NSAppleScript(source: script) else {
            return SectionResult(items: [], status: "Internal: couldn't compile Outlook script.")
        }

        let result = apple.executeAndReturnError(&error)
        if let err = error {
            let msg = (err[NSAppleScript.errorMessage] as? String) ?? "Outlook AppleScript failed."
            // Common cause: user has the "New Outlook" experience which strips AppleScript.
            return SectionResult(items: [], status: "Outlook: \(msg). If you're on the New Outlook, switch back to legacy Outlook (Outlook menu → New Outlook → off) or grant Automation access in System Settings → Privacy & Security → Automation.")
        }

        let text = result.stringValue ?? ""
        let lines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let isoFallback = ISO8601DateFormatter()
        isoFallback.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var items: [DigestItem] = []
        for line in lines {
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            let subject = String(parts[0])
            let sender = String(parts[1])
            let dateString = String(parts[2])

            let date = isoFormatter.date(from: dateString)
                ?? isoFallback.date(from: dateString)

            let isVIP = vipSenders.contains { vip in
                let v = vip.lowercased()
                return !v.isEmpty && (sender.lowercased().contains(v) || subject.lowercased().contains(v))
            }
            let priority = isVIP ? 90 : 50

            items.append(DigestItem(
                source: .outlook,
                title: subject.isEmpty ? "(no subject)" : subject,
                subtitle: sender,
                timestamp: date,
                priority: priority,
                openURL: nil
            ))
        }

        if items.isEmpty {
            return SectionResult(items: [], status: "No unread Outlook mail in the last 24h.")
        }
        return SectionResult(items: items, status: nil)
    }
}
