import AppKit
import EventKit
import UserNotifications

/// App-wide source of truth for open todos. Keeps a fresh `TodoSnapshot` in
/// the background — on Reminders changes (any device, via iCloud), once a
/// minute (so todos tip into "overdue" on time), and on wake — and feeds the
/// menu-bar badge, the menu's todo list, Mission Control, and overdue nudges.
@MainActor
final class TodoMonitor: ObservableObject {

    static let shared = TodoMonitor()

    @Published private(set) var snapshot: TodoSnapshot = .empty
    @Published private(set) var hasLoaded = false

    /// Called after every snapshot change (menu-bar badge hook).
    var onChange: ((TodoSnapshot) -> Void)?

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var isRefreshing = false
    private var refreshQueued = false
    private var nudges = OverdueNudgeSchedule()

    nonisolated static let nudgeIdentifier = "brp.overdue-nudge"

    func start() {
        guard timer == nil else { return }

        observers.append(NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: RemindersFetcher.store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    /// Fire-and-forget refresh. Bursts (EventKit posts several change
    /// notifications per save) collapse into at most one follow-up fetch.
    func refresh() {
        Task { await refreshNow() }
    }

    func refreshNow() async {
        if isRefreshing { refreshQueued = true; return }
        isRefreshing = true
        defer { isRefreshing = false }

        repeat {
            refreshQueued = false
            let cfg = ConfigManager.shared.config.missionControl
            let snap = cfg.includeReminders
                ? await RemindersFetcher.fetchSnapshot(hours: cfg.lookbackHours)
                : TodoSnapshot(items: [], overdueCount: 0, dueTodayCount: 0, status: "Todos disabled in config.")
            apply(snap)
            nudgeIfNeeded(snap, everyMinutes: cfg.includeReminders ? cfg.overdueNudgeMinutes : 0)
        } while refreshQueued
    }

    // MARK: - Actions (optimistic: the row disappears immediately)

    func add(title: String, dueDate: Date?) async {
        await RemindersFetcher.addReminder(title: title, dueDate: dueDate)
        await refreshNow()
    }

    func complete(identifier: String) async {
        apply(snapshot.removing(identifier: identifier))
        await RemindersFetcher.complete(identifier: identifier)
        await refreshNow()
    }

    func snooze(identifier: String, until: Date) async {
        apply(snapshot.removing(identifier: identifier))
        await RemindersFetcher.snooze(identifier: identifier, until: until)
        await refreshNow()
    }

    // MARK: - Internals

    private func apply(_ snap: TodoSnapshot) {
        snapshot = snap
        hasLoaded = true
        onChange?(snap)
    }

    private func nudgeIfNeeded(_ snap: TodoSnapshot, everyMinutes: Int) {
        guard nudges.shouldNudge(overdueCount: snap.overdueCount, everyMinutes: everyMinutes, now: Date()) else { return }
        postNudge(snap)
    }

    private func postNudge(_ snap: TodoSnapshot) {
        // UNUserNotificationCenter needs a real .app bundle (see AppLauncher.notify).
        guard Bundle.main.bundleIdentifier != nil else {
            NSLog("BrotherPaul: %d overdue todo(s) (no bundle — skipping nudge)", snap.overdueCount)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = snap.overdueCount == 1 ? "1 overdue todo" : "\(snap.overdueCount) overdue todos"
        content.body = Self.nudgeBody(snap.items.filter { $0.priority >= 100 }.map(\.title))
        content.sound = .default
        content.categoryIdentifier = Self.nudgeIdentifier

        // Fixed identifier: each nudge replaces the previous one instead of piling up.
        let request = UNNotificationRequest(identifier: Self.nudgeIdentifier, content: content, trigger: nil)
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            try? await center.add(request)
        }
    }

    nonisolated static func nudgeBody(_ titles: [String], limit: Int = 3) -> String {
        var lines = titles.prefix(limit).map { "• \($0)" }
        if titles.count > limit { lines.append("+ \(titles.count - limit) more") }
        return lines.joined(separator: "\n")
    }
}

/// When to nag about overdue todos. Pure + unit-tested.
///
/// - Overdue already at launch → nudge on the first check (you just sat down).
/// - Something tips into overdue later → wait one interval (the reminder's own
///   alarm already fired at the due time), then repeat every interval.
/// - Nothing overdue → reset.
struct OverdueNudgeSchedule {
    private(set) var nextNudgeAt: Date?
    private var isFirstCheck = true

    mutating func shouldNudge(overdueCount: Int, everyMinutes: Int, now: Date) -> Bool {
        defer { isFirstCheck = false }
        guard everyMinutes > 0, overdueCount > 0 else {
            nextNudgeAt = nil
            return false
        }
        let interval = TimeInterval(everyMinutes * 60)
        guard let next = nextNudgeAt else {
            if isFirstCheck {
                nextNudgeAt = now.addingTimeInterval(interval)
                return true
            }
            nextNudgeAt = now.addingTimeInterval(interval)
            return false
        }
        guard now >= next else { return false }
        nextNudgeAt = now.addingTimeInterval(interval)
        return true
    }
}

extension TodoSnapshot {
    /// Rebuild counts from items' priorities (100 = overdue, 70–90 = due today).
    init(items: [DigestItem], status: String?) {
        self.init(
            items: items,
            overdueCount: items.filter { $0.priority >= 100 }.count,
            dueTodayCount: items.filter { (70..<100).contains($0.priority) }.count,
            status: status
        )
    }

    func removing(identifier: String) -> TodoSnapshot {
        let remaining = items.filter { $0.externalID != identifier }
        return TodoSnapshot(items: remaining, status: remaining.isEmpty ? "No open todos." : status)
    }
}
