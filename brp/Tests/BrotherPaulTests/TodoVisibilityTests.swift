import XCTest
@testable import BrotherPaul

/// Todo-visibility logic: date-only due dates, menu-bar badge, overdue nudge
/// schedule, quick-capture date parsing, and snooze targets. All pure — no
/// EventKit permission needed.
final class TodoVisibilityTests: XCTestCase {

    private let cal = Calendar.current

    private func today(_ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }

    private func item(priority: Int, id: String) -> DigestItem {
        DigestItem(source: .reminders, title: id, subtitle: nil, timestamp: nil,
                   priority: priority, openURL: nil, externalID: id)
    }

    // MARK: - Date-only reminders

    func test_dateOnly_components_are_allDay() {
        let comps = cal.dateComponents([.year, .month, .day], from: Date())
        XCTAssertEqual(TodoDue(components: comps)?.isAllDay, true)
        let timed = cal.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
        XCTAssertEqual(TodoDue(components: timed)?.isAllDay, false)
        XCTAssertNil(TodoDue(components: nil))
    }

    func test_dateOnly_due_today_is_not_overdue_in_the_morning() {
        // Regression: a date-only reminder (midnight) used to read "Overdue · 12:00 AM" all day.
        let due = TodoDue(date: cal.startOfDay(for: Date()), isAllDay: true)
        let morning = today(9)
        XCTAssertFalse(due.isOverdue(now: morning))
        XCTAssertEqual(RemindersFetcher.priority(due: due, now: morning), 70)
        XCTAssertEqual(RemindersFetcher.subtitle(due: due, now: morning), "Due today")
    }

    func test_dateOnly_due_yesterday_is_overdue() {
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date()))!
        let due = TodoDue(date: yesterday, isAllDay: true)
        XCTAssertTrue(due.isOverdue(now: today(9)))
        XCTAssertEqual(RemindersFetcher.priority(due: due, now: today(9)), 100)
        XCTAssertTrue(RemindersFetcher.subtitle(due: due, now: today(9)).hasPrefix("Overdue"))
    }

    func test_timed_due_past_is_overdue() {
        let due = TodoDue(date: today(8), isAllDay: false)
        XCTAssertEqual(RemindersFetcher.priority(due: due, now: today(9)), 100)
    }

    func test_subtitle_appends_custom_list_name_only() {
        let due = TodoDue(date: cal.startOfDay(for: Date()), isAllDay: true)
        XCTAssertEqual(RemindersFetcher.subtitle(due: due, now: today(9), listName: "Work"), "Due today  ·  Work")
        XCTAssertEqual(RemindersFetcher.subtitle(due: due, now: today(9), listName: "Reminders"), "Due today")
        XCTAssertEqual(RemindersFetcher.subtitle(due: nil, now: today(9)), "No due date")
    }

    // MARK: - Snapshot counts

    func test_snapshot_counts_from_priorities() {
        let snap = TodoSnapshot(items: [
            item(priority: 100, id: "a"), item(priority: 90, id: "b"),
            item(priority: 70, id: "c"), item(priority: 55, id: "d"), item(priority: 40, id: "e"),
        ], status: nil)
        XCTAssertEqual(snap.overdueCount, 1)
        XCTAssertEqual(snap.dueTodayCount, 2)
        XCTAssertEqual(snap.attentionCount, 3)
    }

    func test_snapshot_removing_updates_counts() {
        let snap = TodoSnapshot(items: [item(priority: 100, id: "a"), item(priority: 40, id: "b")], status: nil)
        let after = snap.removing(identifier: "a")
        XCTAssertEqual(after.items.map(\.title), ["b"])
        XCTAssertEqual(after.overdueCount, 0)
        XCTAssertEqual(snap.removing(identifier: "a").removing(identifier: "b").status, "No open todos.")
    }

    // MARK: - Menu-bar badge

    func test_badge_overdue_is_red_level_with_count() {
        let snap = TodoSnapshot(items: [], overdueCount: 2, dueTodayCount: 1, status: nil)
        let badge = TodoBadge(snapshot: snap, enabled: true)
        XCTAssertEqual(badge.level, .overdue)
        XCTAssertEqual(badge.text, " 3")
        XCTAssertEqual(badge.toolTip, "Brother Paul — 2 overdue, 1 due today")
    }

    func test_badge_due_today_only() {
        let badge = TodoBadge(snapshot: TodoSnapshot(items: [], overdueCount: 0, dueTodayCount: 1, status: nil), enabled: true)
        XCTAssertEqual(badge.level, .dueToday)
        XCTAssertEqual(badge.text, " 1")
    }

    func test_badge_empty_when_nothing_due_or_disabled() {
        XCTAssertEqual(TodoBadge(snapshot: .empty, enabled: true).text, "")
        XCTAssertEqual(TodoBadge(snapshot: .empty, enabled: true).level, .none)
        let busy = TodoSnapshot(items: [], overdueCount: 4, dueTodayCount: 0, status: nil)
        XCTAssertEqual(TodoBadge(snapshot: busy, enabled: false).text, "")
        XCTAssertEqual(TodoBadge(snapshot: busy, enabled: false).level, .none)
    }

    // MARK: - Overdue nudge schedule

    func test_nudge_immediately_when_overdue_at_launch_then_every_interval() {
        var s = OverdueNudgeSchedule()
        let t0 = Date()
        XCTAssertTrue(s.shouldNudge(overdueCount: 2, everyMinutes: 60, now: t0))
        XCTAssertFalse(s.shouldNudge(overdueCount: 2, everyMinutes: 60, now: t0.addingTimeInterval(30 * 60)))
        XCTAssertTrue(s.shouldNudge(overdueCount: 2, everyMinutes: 60, now: t0.addingTimeInterval(61 * 60)))
    }

    func test_nudge_waits_one_interval_when_todo_tips_overdue_later() {
        var s = OverdueNudgeSchedule()
        let t0 = Date()
        XCTAssertFalse(s.shouldNudge(overdueCount: 0, everyMinutes: 60, now: t0))
        // Becomes overdue: its own alarm just fired, so don't double up.
        XCTAssertFalse(s.shouldNudge(overdueCount: 1, everyMinutes: 60, now: t0.addingTimeInterval(60)))
        XCTAssertTrue(s.shouldNudge(overdueCount: 1, everyMinutes: 60, now: t0.addingTimeInterval(62 * 60)))
    }

    func test_nudge_resets_when_cleared_and_respects_disable() {
        var s = OverdueNudgeSchedule()
        let t0 = Date()
        XCTAssertTrue(s.shouldNudge(overdueCount: 1, everyMinutes: 60, now: t0))
        XCTAssertFalse(s.shouldNudge(overdueCount: 0, everyMinutes: 60, now: t0.addingTimeInterval(60)))
        XCTAssertNil(s.nextNudgeAt)

        var off = OverdueNudgeSchedule()
        XCTAssertFalse(off.shouldNudge(overdueCount: 5, everyMinutes: 0, now: t0))
    }

    func test_nudge_body_lists_first_three() {
        XCTAssertEqual(TodoMonitor.nudgeBody(["a", "b"]), "• a\n• b")
        XCTAssertEqual(TodoMonitor.nudgeBody(["a", "b", "c", "d", "e"]), "• a\n• b\n• c\n+ 2 more")
    }

    // MARK: - Quick-capture parsing

    func test_parser_extracts_future_date_and_cleans_title() throws {
        let r = TodoParser.parse("Email Bob tomorrow at 3pm")
        XCTAssertEqual(r.title, "Email Bob")
        let due = try XCTUnwrap(r.dueDate)
        XCTAssertTrue(cal.isDateInTomorrow(due))
        XCTAssertEqual(cal.component(.hour, from: due), 15)
    }

    func test_parser_leaves_plain_titles_alone() {
        XCTAssertEqual(TodoParser.parse("  Review the Q3 report "), .init(title: "Review the Q3 report", dueDate: nil))
    }

    func test_parser_ignores_past_dates() {
        let r = TodoParser.parse("Follow up on the January 3, 2020 incident")
        XCTAssertNil(r.dueDate)
        XCTAssertEqual(r.title, "Follow up on the January 3, 2020 incident")
    }

    // MARK: - Snooze targets

    func test_snooze_targets() {
        let morning = today(10)
        XCTAssertEqual(RemindersFetcher.SnoozeOption.oneHour.target(from: morning), today(11))
        XCTAssertEqual(RemindersFetcher.SnoozeOption.thisEvening.target(from: morning), today(17))
        XCTAssertNil(RemindersFetcher.SnoozeOption.thisEvening.target(from: today(18)))
        let tomorrow9 = RemindersFetcher.SnoozeOption.tomorrowMorning.target(from: morning)!
        XCTAssertTrue(cal.isDateInTomorrow(tomorrow9))
        XCTAssertEqual(cal.component(.hour, from: tomorrow9), 9)
    }

    // MARK: - Config

    func test_visibility_config_defaults_when_absent() throws {
        let cfg = try JSONDecoder().decode(MissionControlConfig.self, from: Data("{}".utf8))
        XCTAssertTrue(cfg.showTodoCountInMenuBar)
        XCTAssertEqual(cfg.overdueNudgeMinutes, 60)
        XCTAssertEqual(cfg.autoRefreshMinutes, 5)
    }

    func test_visibility_config_explicit_values() throws {
        let json = #"{"showTodoCountInMenuBar": false, "overdueNudgeMinutes": 0, "autoRefreshMinutes": 15}"#
        let cfg = try JSONDecoder().decode(MissionControlConfig.self, from: Data(json.utf8))
        XCTAssertFalse(cfg.showTodoCountInMenuBar)
        XCTAssertEqual(cfg.overdueNudgeMinutes, 0)
        XCTAssertEqual(cfg.autoRefreshMinutes, 15)
    }
}
