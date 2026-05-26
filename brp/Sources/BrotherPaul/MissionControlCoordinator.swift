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

        async let gmail: SectionResult = cfg.includeGmail
            ? GmailFetcher.fetchUnread(config: cfg.gmail, vipSenders: cfg.vipSenders)
            : SectionResult(items: [], status: nil)

        async let notifications: SectionResult = cfg.includeNotifications
            ? NotificationsFetcher.fetchRecent(hours: cfg.lookbackHours, appBlocklist: cfg.notificationAppBlocklist)
            : SectionResult(items: [], status: "Notifications disabled in config.")

        let (ek, oc, gc, o, g, n) = await (eventKitEvents, outlookEvents, graphEvents, outlook, gmail, notifications)

        let events = mergeEvents(
            eventKit: ek,
            outlook: oc,
            graph: gc,
            includingEventKit: cfg.includeCalendar,
            includingOutlook: cfg.includeOutlookCalendar,
            includingGraph: cfg.includeGraphCalendar
        )
        let emails = mergeEmail(outlook: o, gmail: g, includingOutlook: cfg.includeOutlook, includingGmail: cfg.includeGmail)

        let verse = cfg.includeVerseOfDay ? VerseOfTheDay.todays() : nil

        self.digest = Digest(
            generatedAt: Date(),
            verse: verse,
            events: events,
            emails: emails,
            notifications: n
        )
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

    private func mergeEmail(outlook: SectionResult, gmail: SectionResult, includingOutlook: Bool, includingGmail: Bool) -> SectionResult {
        var items = outlook.items + gmail.items
        items.sort {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast)
        }

        var statuses: [String] = []
        if includingOutlook, let s = outlook.status { statuses.append("Outlook: \(s)") }
        if includingGmail,  let s = gmail.status   { statuses.append("Gmail: \(s)") }
        if !includingOutlook && !includingGmail { statuses.append("All email sources disabled.") }

        return SectionResult(items: items, status: statuses.isEmpty ? nil : statuses.joined(separator: "  •  "))
    }
}
