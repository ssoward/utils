import Foundation
import EventKit

/// Bridges Brother Paul to the macOS Reminders app via EventKit. Todos are
/// real EKReminders, so they sync with iCloud / iPhone and — because we attach
/// an EKAlarm at the due date — the system fires a native notification when a
/// reminder comes due, even if Brother Paul isn't the frontmost app.
enum RemindersFetcher {

    // MARK: - Read

    /// Incomplete reminders that are overdue, undated, or due within `hours`.
    /// Sorted soonest-first; undated reminders sink to the bottom.
    static func fetchReminders(hours: Int) async -> SectionResult {
        let store = EKEventStore()

        guard await requestAccess(store: store) else {
            return SectionResult(items: [], status: "Reminders access denied — grant in System Settings → Privacy & Security → Reminders.")
        }

        let now = Date()
        let all = await incompleteReminders(store: store)
        let visible = all
            .filter { isWithinWindow(dueDate: dueDate(for: $0), now: now, hours: hours) }
            .sorted { ($0.dueDateSortKey ?? .distantFuture) < ($1.dueDateSortKey ?? .distantFuture) }

        let items = visible.map { reminder -> DigestItem in
            let due = dueDate(for: reminder)
            return DigestItem(
                source: .reminders,
                title: reminder.title ?? "(untitled)",
                subtitle: subtitle(for: reminder, due: due, now: now),
                timestamp: due,
                priority: priority(dueDate: due, now: now),
                openURL: nil,
                externalID: reminder.calendarItemIdentifier
            )
        }

        let status = items.isEmpty ? "No open todos." : nil
        return SectionResult(items: items, status: status)
    }

    // MARK: - Write

    /// Create a reminder in the default Reminders list. When `dueDate` is set we
    /// attach an absolute alarm so macOS delivers a system notification when due.
    /// Returns the new reminder's identifier, or nil on failure.
    @discardableResult
    static func addReminder(title: String, notes: String? = nil, dueDate: Date? = nil) async -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let store = EKEventStore()
        guard await requestAccess(store: store) else { return nil }
        guard let calendar = store.defaultCalendarForNewReminders() else { return nil }

        let reminder = EKReminder(eventStore: store)
        reminder.title = trimmed
        reminder.notes = notes
        reminder.calendar = calendar

        if let due = dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due
            )
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }

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
        let store = EKEventStore()
        guard await requestAccess(store: store) else { return false }
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

    // MARK: - Pure helpers (unit-tested; no EventKit permission needed)

    /// Higher = more urgent. Overdue tops the list; undated sinks lowest.
    static func priority(dueDate: Date?, now: Date = Date()) -> Int {
        guard let due = dueDate else { return 40 }
        if due < now { return 100 }                                  // overdue
        if due.timeIntervalSince(now) <= 3600 { return 90 }          // within the hour
        if Calendar.current.isDateInToday(due) { return 70 }         // later today
        return 55                                                    // upcoming
    }

    /// A reminder is shown when it's undated (always), overdue, or due on/before
    /// the look-ahead horizon `now + hours`.
    static func isWithinWindow(dueDate: Date?, now: Date, hours: Int) -> Bool {
        guard let due = dueDate else { return true }
        let horizon = now.addingTimeInterval(TimeInterval(hours * 3600))
        return due <= horizon
    }

    /// Human-readable subtitle: "Overdue · Mon 9:00 AM", "Due 2:30 PM", or "No due date".
    static func subtitle(for reminder: EKReminder, due: Date?, now: Date) -> String {
        guard let due = due else { return "No due date" }
        let f = DateFormatter()
        let cal = Calendar.current
        if cal.isDateInToday(due) {
            f.dateStyle = .none; f.timeStyle = .short
        } else {
            f.dateFormat = "EEE h:mm a"
        }
        let when = f.string(from: due)
        return due < now ? "Overdue · \(when)" : "Due \(when)"
    }

    // MARK: - EventKit plumbing

    private static func dueDate(for reminder: EKReminder) -> Date? {
        guard let comps = reminder.dueDateComponents else { return nil }
        return Calendar.current.date(from: comps)
    }

    private static func requestAccess(store: EKEventStore) async -> Bool {
        if #available(macOS 14.0, *) {
            return (try? await store.requestFullAccessToReminders()) ?? false
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            store.requestAccess(to: .reminder) { granted, _ in
                cont.resume(returning: granted)
            }
        }
    }

    private static func incompleteReminders(store: EKEventStore) async -> [EKReminder] {
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

private extension EKReminder {
    /// Concrete Date for sorting; nil when the reminder has no due date.
    var dueDateSortKey: Date? {
        guard let comps = dueDateComponents else { return nil }
        return Calendar.current.date(from: comps)
    }
}
