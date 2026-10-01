import Foundation
import EventKit
import AppKit

/// Open todos plus the counts that drive the menu-bar badge and nudges.
struct TodoSnapshot {
    var items: [DigestItem]
    /// Past due (timed reminders past their time; date-only reminders from a previous day).
    var overdueCount: Int
    /// Due later today (not yet overdue).
    var dueTodayCount: Int
    /// User-facing status when there's nothing to show (access denied, disabled, …).
    var status: String?

    static let empty = TodoSnapshot(items: [], overdueCount: 0, dueTodayCount: 0, status: nil)

    var section: SectionResult { SectionResult(items: items, status: items.isEmpty ? status : nil) }

    /// Number shown next to the menu-bar icon: things that need attention today.
    var attentionCount: Int { overdueCount + dueTodayCount }
}

/// Bridges Brother Paul to the macOS Reminders app via EventKit. Todos are
/// real EKReminders, so they sync with iCloud / iPhone and — because we attach
/// an EKAlarm at the due date — the system fires a native notification when a
/// reminder comes due, even if Brother Paul isn't the frontmost app.
enum RemindersFetcher {

    /// One long-lived store for the whole app (Apple's guidance: creating an
    /// EKEventStore is expensive, and change notifications are per-instance).
    static let store = EKEventStore()

    // MARK: - Read

    /// Incomplete reminders that are overdue, undated, or due within `hours`.
    /// Sorted overdue → soonest → undated.
    static func fetchSnapshot(hours: Int) async -> TodoSnapshot {
        guard await requestAccess() else {
            return TodoSnapshot(items: [], overdueCount: 0, dueTodayCount: 0,
                                status: "Reminders access denied — grant in System Settings → Privacy & Security → Reminders.")
        }

        let now = Date()
        let all = await incompleteReminders()
        let todos = all.map { (reminder: $0, due: TodoDue(components: $0.dueDateComponents)) }
            .filter { isWithinWindow(due: $0.due, now: now, hours: hours) }
            .sorted { sortKey($0.due) < sortKey($1.due) }

        let items = todos.map { todo in
            DigestItem(
                source: .reminders,
                title: todo.reminder.title ?? "(untitled)",
                subtitle: subtitle(due: todo.due, now: now, listName: todo.reminder.calendar?.title),
                timestamp: todo.due?.date,
                priority: priority(due: todo.due, now: now),
                openURL: nil,
                externalID: todo.reminder.calendarItemIdentifier
            )
        }

        return TodoSnapshot(items: items, status: items.isEmpty ? "No open todos." : nil)
    }

    static func fetchReminders(hours: Int) async -> SectionResult {
        await fetchSnapshot(hours: hours).section
    }

    // MARK: - Write

    /// Create a reminder in the default Reminders list. When `dueDate` is set we
    /// attach an absolute alarm so macOS delivers a system notification when due.
    /// Returns the new reminder's identifier, or nil on failure.
    @discardableResult
    static func addReminder(title: String, notes: String? = nil, dueDate: Date? = nil) async -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard await requestAccess() else { return nil }
        guard let calendar = store.defaultCalendarForNewReminders() else { return nil }

        let reminder = EKReminder(eventStore: store)
        reminder.title = trimmed
        reminder.notes = notes
        reminder.calendar = calendar
        if let due = dueDate { setDue(due, on: reminder) }

        do {
            try store.save(reminder, commit: true)
            return reminder.calendarItemIdentifier
        } catch {
            NSLog("BrotherPaul: failed to save reminder — %@", error.localizedDescription)
            return nil
        }
    }

    /// Mark the reminder with the given identifier complete.
    @discardableResult
    static func complete(identifier: String) async -> Bool {
        guard await requestAccess() else { return false }
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return false }

        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            NSLog("BrotherPaul: failed to complete reminder — %@", error.localizedDescription)
            return false
        }
    }

    /// Move a reminder's due time to `until` and re-arm its alarm.
    @discardableResult
    static func snooze(identifier: String, until: Date) async -> Bool {
        guard await requestAccess() else { return false }
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return false }

        setDue(until, on: reminder)
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            NSLog("BrotherPaul: failed to snooze reminder — %@", error.localizedDescription)
            return false
        }
    }

    static func openRemindersApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private static func setDue(_ due: Date, on reminder: EKReminder) {
        reminder.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: due
        )
        reminder.alarms?.forEach { reminder.removeAlarm($0) }
        reminder.addAlarm(EKAlarm(absoluteDate: due))
    }

    // MARK: - Snooze targets

    enum SnoozeOption: CaseIterable {
        case oneHour, thisEvening, tomorrowMorning

        var title: String {
            switch self {
            case .oneHour:         return "Snooze 1 Hour"
            case .thisEvening:     return "Snooze to This Evening"
            case .tomorrowMorning: return "Snooze to Tomorrow 9 AM"
            }
        }

        /// nil when the option doesn't make sense right now (e.g. "this evening" after 5 PM).
        func target(from now: Date = Date(), calendar: Calendar = .current) -> Date? {
            switch self {
            case .oneHour:
                return now.addingTimeInterval(3600)
            case .thisEvening:
                guard let fivePM = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now),
                      fivePM > now.addingTimeInterval(15 * 60) else { return nil }
                return fivePM
            case .tomorrowMorning:
                guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
                return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
            }
        }
    }

    // MARK: - Pure helpers (unit-tested; no EventKit permission needed)

    /// Higher = more urgent. Overdue tops the list; undated sinks lowest.
    static func priority(dueDate: Date?, now: Date = Date()) -> Int {
        priority(due: dueDate.map { TodoDue(date: $0, isAllDay: false) }, now: now)
    }

    static func priority(due: TodoDue?, now: Date = Date()) -> Int {
        guard let due = due else { return 40 }
        if due.isOverdue(now: now) { return 100 }                    // overdue
        if !due.isAllDay, due.date.timeIntervalSince(now) <= 3600 { return 90 } // within the hour
        if Calendar.current.isDate(due.date, inSameDayAs: now) { return 70 }   // later today
        return 55                                                    // upcoming
    }

    /// A reminder is shown when it's undated (always), overdue, or due on/before
    /// the look-ahead horizon `now + hours`.
    static func isWithinWindow(dueDate: Date?, now: Date, hours: Int) -> Bool {
        isWithinWindow(due: dueDate.map { TodoDue(date: $0, isAllDay: false) }, now: now, hours: hours)
    }

    static func isWithinWindow(due: TodoDue?, now: Date, hours: Int) -> Bool {
        guard let due = due else { return true }
        let horizon = now.addingTimeInterval(TimeInterval(hours * 3600))
        return due.date <= horizon
    }

    /// Human-readable subtitle: "Overdue · Mon 9:00 AM", "Due 2:30 PM", "Due today", or "No due date".
    /// The Reminders list name is appended when it isn't the generic default.
    static func subtitle(due: TodoDue?, now: Date, listName: String? = nil) -> String {
        let base: String
        if let due = due {
            let cal = Calendar.current
            let when: String
            if due.isAllDay {
                if cal.isDate(due.date, inSameDayAs: now) { when = "today" }
                else if cal.isDateInTomorrow(due.date) { when = "tomorrow" }
                else { when = Formatters.weekdayDate.string(from: due.date) }
            } else if cal.isDate(due.date, inSameDayAs: now) {
                when = Formatters.time.string(from: due.date)
            } else {
                when = Formatters.weekdayTime.string(from: due.date)
            }
            base = due.isOverdue(now: now) ? "Overdue · \(when)" : "Due \(when)"
        } else {
            base = "No due date"
        }
        guard let list = listName, !list.isEmpty,
              !["Reminders", "Inbox"].contains(list) else { return base }
        return "\(base)  ·  \(list)"
    }

    private static func sortKey(_ due: TodoDue?) -> Date {
        due?.deadline ?? .distantFuture
    }

    // MARK: - EventKit plumbing

    private static func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if #available(macOS 14.0, *) {
            if status == .fullAccess { return true }
        } else if status == .authorized {
            return true
        }
        if status == .denied || status == .restricted { return false }

        if #available(macOS 14.0, *) {
            return (try? await store.requestFullAccessToReminders()) ?? false
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            store.requestAccess(to: .reminder) { granted, _ in
                cont.resume(returning: granted)
            }
        }
    }

    private static func incompleteReminders() async -> [EKReminder] {
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )
        return await withCheckedContinuation { (cont: CheckedContinuation<[EKReminder], Never>) in
            store.fetchReminders(matching: predicate) { reminders in
                cont.resume(returning: reminders ?? [])
            }
        }
    }
}

/// A reminder's due date. Reminders created as "date only" (no time) have
/// day-level components; they're due *by the end of* that day, so they must not
/// read as "Overdue · 12:00 AM" all morning.
struct TodoDue: Equatable {
    let date: Date
    let isAllDay: Bool

    init(date: Date, isAllDay: Bool) {
        self.date = date
        self.isAllDay = isAllDay
    }

    init?(components: DateComponents?, calendar: Calendar = .current) {
        guard let comps = components, let date = calendar.date(from: comps) else { return nil }
        self.date = date
        self.isAllDay = comps.hour == nil
    }

    /// The moment the todo becomes overdue.
    var deadline: Date {
        guard isAllDay else { return date }
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date)) ?? date
    }

    func isOverdue(now: Date) -> Bool { deadline <= now }
}

/// Formatters are expensive to build; share them.
enum Formatters {
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
    static let weekdayTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        return f
    }()
    static let weekdayDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f
    }()
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
