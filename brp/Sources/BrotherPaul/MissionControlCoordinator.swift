import Foundation

@MainActor
final class MissionControlCoordinator: ObservableObject {

    @Published var digest: Digest?
    @Published var isLoading: Bool = false

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let cfg = ConfigManager.shared.config.missionControl

        async let eventKitEvents: SectionResult = cfg.includeCalendar
            ? CalendarFetcher.fetchUpcoming(hours: cfg.lookbackHours)
            : SectionResult(items: [], status: nil)

        async let outlookEvents: SectionResult = cfg.includeOutlookCalendar
            ? OutlookCalendarFetcher.fetchUpcoming()
            : SectionResult(items: [], status: nil)

        async let graphEvents: SectionResult = cfg.includeGraphCalendar
            ? GraphCalendarFetcher.fetchUpcoming(config: cfg.graph, hours: cfg.lookbackHours)
            : SectionResult(items: [], status: nil)

        async let outlook: SectionResult = cfg.includeOutlook
            ? OutlookFetcher.fetchUnread(vipSenders: cfg.vipSenders)
            : SectionResult(items: [], status: nil)

        async let graphMail: SectionResult = cfg.includeGraphMail
            ? GraphMailFetcher.fetchUnread(config: cfg.graph, vipSenders: cfg.vipSenders, hours: cfg.lookbackHours)
            : SectionResult(items: [], status: nil)

        async let gmail: SectionResult = cfg.includeGmail
            ? GmailFetcher.fetchUnread(config: cfg.gmail, vipSenders: cfg.vipSenders)
            : SectionResult(items: [], status: nil)

        async let reminders: SectionResult = cfg.includeReminders
            ? RemindersFetcher.fetchReminders(hours: cfg.lookbackHours)
            : SectionResult(items: [], status: "Todos disabled in config.")

        async let notifications: SectionResult = cfg.includeNotifications
            ? NotificationsFetcher.fetchRecent(hours: cfg.lookbackHours, appBlocklist: cfg.notificationAppBlocklist)
            : SectionResult(items: [], status: "Notifications disabled in config.")

        let (ek, oc, gc, o, gm, g, r, n) = await (eventKitEvents, outlookEvents, graphEvents, outlook, graphMail, gmail, reminders, notifications)

        let events = mergeEvents(
            eventKit: ek,
            outlook: oc,
            graph: gc,
            includingEventKit: cfg.includeCalendar,
            includingOutlook: cfg.includeOutlookCalendar,
            includingGraph: cfg.includeGraphCalendar
        )
        let emails = mergeEmail(
            outlook: o,
            graphMail: gm,
            gmail: g,
            includingOutlook: cfg.includeOutlook,
            includingGraphMail: cfg.includeGraphMail,
            includingGmail: cfg.includeGmail
        )

        let verse = cfg.includeVerseOfDay ? VerseOfTheDay.todays() : nil

        self.digest = Digest(
            generatedAt: Date(),
            verse: verse,
            events: events,
            emails: emails,
            reminders: r,
            notifications: n
        )
    }

    /// Add a todo (an EKReminder) and refresh so it appears in the digest.
    func addTodo(title: String, dueDate: Date?) async {
        await RemindersFetcher.addReminder(title: title, dueDate: dueDate)
        await refresh()
    }

    /// Mark a todo complete and refresh so it drops off the list.
    func completeTodo(identifier: String) async {
        await RemindersFetcher.complete(identifier: identifier)
        await refresh()
    }

    /// Replace the currently-shown verse with a random different one from the
    /// same pool. Ephemeral — a full refresh resets to today's verse.
    func shuffleVerse() {
        guard var current = digest else { return }
        current.verse = VerseOfTheDay.randomVerse(excluding: current.verse)
        digest = current
    }

    private func mergeEvents(
        eventKit: SectionResult,
        outlook: SectionResult,
        graph: SectionResult,
        includingEventKit: Bool,
        includingOutlook: Bool,
        includingGraph: Bool
    ) -> SectionResult {
        var items = eventKit.items + outlook.items + graph.items

        // Dedup: same title (case-insensitive) and start time within ±60s.
        var kept: [DigestItem] = []
        for item in items {
            let duplicate = kept.contains { existing in
                guard
                    let a = item.timestamp,
                    let b = existing.timestamp
                else { return false }
                return existing.title.caseInsensitiveCompare(item.title) == .orderedSame
                    && abs(a.timeIntervalSince(b)) < 60
            }
            if !duplicate { kept.append(item) }
        }
        items = kept.sorted { ($0.timestamp ?? .distantFuture) < ($1.timestamp ?? .distantFuture) }

        var statuses: [String] = []
        if includingEventKit, let s = eventKit.status, !s.isEmpty { statuses.append("Calendar: \(s)") }
        if includingOutlook,  let s = outlook.status,  !s.isEmpty { statuses.append("Outlook: \(s)") }
        if includingGraph,    let s = graph.status,    !s.isEmpty { statuses.append("Graph: \(s)") }
        if !includingEventKit && !includingOutlook && !includingGraph {
            statuses.append("All calendar sources disabled.")
        }

        return SectionResult(items: items, status: statuses.isEmpty ? nil : statuses.joined(separator: "  •  "))
    }

    private func mergeEmail(
        outlook: SectionResult,
        graphMail: SectionResult,
        gmail: SectionResult,
        includingOutlook: Bool,
        includingGraphMail: Bool,
        includingGmail: Bool
    ) -> SectionResult {
        // Both AppleScript Outlook and Graph mail target the same inbox; if a
        // user has both on (e.g. while migrating off Legacy), de-dup by
        // (subject, sender) so messages don't appear twice.
        var seen = Set<String>()
        var deduped: [DigestItem] = []
        for item in outlook.items + graphMail.items + gmail.items {
            let key = "\(item.title.lowercased())|\((item.subtitle ?? "").lowercased())"
            if seen.insert(key).inserted {
                deduped.append(item)
            }
        }
        deduped.sort {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast)
        }

        var statuses: [String] = []
        if includingOutlook,   let s = outlook.status   { statuses.append("Outlook: \(s)") }
        if includingGraphMail, let s = graphMail.status { statuses.append("Graph: \(s)") }
        if includingGmail,     let s = gmail.status     { statuses.append("Gmail: \(s)") }
        if !includingOutlook && !includingGraphMail && !includingGmail {
            statuses.append("All email sources disabled.")
        }

        return SectionResult(items: deduped, status: statuses.isEmpty ? nil : statuses.joined(separator: "  •  "))
    }
}
