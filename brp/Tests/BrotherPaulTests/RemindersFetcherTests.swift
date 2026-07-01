import XCTest
@testable import BrotherPaul

/// Pure-logic tests for the reminders/todos feature. The EventKit read/write
/// paths need Reminders permission and a live store, so they're exercised by
/// the app itself; here we lock down the priority + windowing math and the
/// config default, which are permission-free and deterministic.
final class RemindersFetcherTests: XCTestCase {

    // MARK: - priority(dueDate:now:)

    func test_priority_undated_is_lowest() {
        XCTAssertEqual(RemindersFetcher.priority(dueDate: nil), 40)
    }

    func test_priority_overdue_is_highest() {
        let now = Date()
        let due = now.addingTimeInterval(-3600) // an hour ago
        XCTAssertEqual(RemindersFetcher.priority(dueDate: due, now: now), 100)
    }

    func test_priority_within_the_hour() {
        let now = Date()
        let due = now.addingTimeInterval(30 * 60) // 30 min out
        XCTAssertEqual(RemindersFetcher.priority(dueDate: due, now: now), 90)
    }

    func test_priority_upcoming_beyond_today() {
        let now = Date()
        let due = now.addingTimeInterval(3 * 24 * 3600) // 3 days out
        XCTAssertEqual(RemindersFetcher.priority(dueDate: due, now: now), 55)
    }

    // MARK: - isWithinWindow(dueDate:now:hours:)

    func test_window_undated_always_included() {
        XCTAssertTrue(RemindersFetcher.isWithinWindow(dueDate: nil, now: Date(), hours: 24))
    }

    func test_window_overdue_included() {
        let now = Date()
        let due = now.addingTimeInterval(-10 * 3600)
        XCTAssertTrue(RemindersFetcher.isWithinWindow(dueDate: due, now: now, hours: 24))
    }

    func test_window_inside_horizon_included() {
        let now = Date()
        let due = now.addingTimeInterval(12 * 3600)
        XCTAssertTrue(RemindersFetcher.isWithinWindow(dueDate: due, now: now, hours: 24))
    }

    func test_window_beyond_horizon_excluded() {
        let now = Date()
        let due = now.addingTimeInterval(48 * 3600)
        XCTAssertFalse(RemindersFetcher.isWithinWindow(dueDate: due, now: now, hours: 24))
    }

    // MARK: - Config default

    func test_includeReminders_defaults_true_when_absent() throws {
        let cfg = try JSONDecoder().decode(MissionControlConfig.self, from: Data("{}".utf8))
        XCTAssertTrue(cfg.includeReminders)
    }

    func test_includeReminders_respects_explicit_false() throws {
        let json = Data(#"{"includeReminders": false}"#.utf8)
        let cfg = try JSONDecoder().decode(MissionControlConfig.self, from: json)
        XCTAssertFalse(cfg.includeReminders)
    }
}
