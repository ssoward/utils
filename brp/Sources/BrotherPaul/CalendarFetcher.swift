import Foundation
import EventKit

enum CalendarFetcher {

    static func fetchUpcoming(hours: Int) async -> SectionResult {
        let store = EKEventStore()

        let granted = await requestAccess(store: store)
        guard granted else {
            return SectionResult(items: [], status: "Calendar access denied — grant in System Settings → Privacy & Security → Calendars.")
        }

        let now = Date()
        let end = Calendar.current.date(byAdding: .hour, value: hours, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay || isToday($0.startDate) }
            .sorted { $0.startDate < $1.startDate }

        let items = events.map { ev -> DigestItem in
            let title = ev.title ?? "(no title)"
            let when = formatEventTime(ev)
            let location = (ev.location?.isEmpty == false) ? "  ·  \(ev.location!)" : ""
            let subtitle = "\(when)\(location)"

            // Earlier = higher priority (within 15 min = top).
            let minutesAway = Int(ev.startDate.timeIntervalSinceNow / 60)
            let priority: Int = {
                if minutesAway <= 15 { return 100 }
                if minutesAway <= 60 { return 80 }
                return 60
            }()

            return DigestItem(
                source: .calendar,
                title: title,
                subtitle: subtitle,
                timestamp: ev.startDate,
                priority: priority,
                openURL: nil
            )
        }

        return SectionResult(items: items, status: items.isEmpty ? "No events in the next \(hours)h" : nil)
    }

    private static func requestAccess(store: EKEventStore) async -> Bool {
        if #available(macOS 14.0, *) {
            return (try? await store.requestFullAccessToEvents()) ?? false
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            store.requestAccess(to: .event) { granted, _ in
                cont.resume(returning: granted)
            }
        }
    }

    private static func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private static func formatEventTime(_ event: EKEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        if event.isAllDay { return "All day" }

        let start = formatter.string(from: event.startDate)
        let end = formatter.string(from: event.endDate)
        let cal = Calendar.current
        if cal.isDateInToday(event.startDate) {
            return "\(start) – \(end)"
        } else {
            let day = DateFormatter()
            day.dateFormat = "EEE"
            return "\(day.string(from: event.startDate)) \(start) – \(end)"
        }
    }
}
