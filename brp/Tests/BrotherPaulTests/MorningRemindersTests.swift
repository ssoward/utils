import XCTest
@testable import BrotherPaul

final class MorningRemindersTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("brpaul-reminders-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        setenv("BROTHERPAUL_CONFIG_DIR", tmp.path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("BROTHERPAUL_CONFIG_DIR")
        try? FileManager.default.removeItem(at: tmp)
    }

    private func writeReminders(_ reminders: [Reminder]) throws {
        let data = try JSONEncoder().encode(reminders)
        try data.write(to: MorningReminders.customFileURL)
    }

    // MARK: - todays(now:)

    func test_todays_is_nil_when_no_file_exists() {
        XCTAssertNil(MorningReminders.todays())
    }

    func test_todays_is_nil_when_file_is_empty_array() throws {
        try writeReminders([])
        XCTAssertNil(MorningReminders.todays())
    }

    func test_todays_is_stable_for_the_same_date() throws {
        try writeReminders([
            Reminder(text: "one"), Reminder(text: "two"), Reminder(text: "three"),
        ])
        let date = makeDate(year: 2026, month: 7, day: 15)
        XCTAssertEqual(MorningReminders.todays(now: date),
                       MorningReminders.todays(now: date))
    }

    func test_todays_rotates_across_days() throws {
        try writeReminders([
            Reminder(text: "one"), Reminder(text: "two"), Reminder(text: "three"),
        ])
        let day1 = makeDate(year: 2026, month: 7, day: 15)
        let day2 = makeDate(year: 2026, month: 7, day: 16)
        XCTAssertNotEqual(MorningReminders.todays(now: day1),
                          MorningReminders.todays(now: day2))
    }

    func test_todays_wraps_modulo_pool_size() throws {
        let pool = [Reminder(text: "one"), Reminder(text: "two"), Reminder(text: "three")]
        try writeReminders(pool)
        let day1 = makeDate(year: 2026, month: 1, day: 1)
        guard let day1PlusN = Calendar.current.date(byAdding: .day, value: pool.count, to: day1)
        else { return XCTFail("date math failed") }
        XCTAssertEqual(MorningReminders.todays(now: day1),
                       MorningReminders.todays(now: day1PlusN))
    }

    func test_todays_picks_up_edits_without_restart() throws {
        try writeReminders([Reminder(text: "before")])
        XCTAssertEqual(MorningReminders.todays()?.text, "before")
        try writeReminders([Reminder(text: "after")])
        XCTAssertEqual(MorningReminders.todays()?.text, "after")
    }

    func test_source_decodes_when_present_and_absent() throws {
        let json = """
        [
          {"text": "with source", "source": "Priesthood blessing"},
          {"text": "without source"}
        ]
        """
        try json.data(using: .utf8)!.write(to: MorningReminders.customFileURL)
        let day1 = makeDate(year: 2026, month: 1, day: 1)
        let day2 = makeDate(year: 2026, month: 1, day: 2)
        XCTAssertEqual(MorningReminders.todays(now: day1)?.source, "Priesthood blessing")
        XCTAssertNil(MorningReminders.todays(now: day2)?.source)
    }

    // MARK: - randomReminder(excluding:)

    func test_randomReminder_is_nil_when_no_file_exists() {
        XCTAssertNil(MorningReminders.randomReminder(excluding: nil))
    }

    func test_randomReminder_excludes_the_passed_reminder() throws {
        let pool = [Reminder(text: "one"), Reminder(text: "two"), Reminder(text: "three")]
        try writeReminders(pool)
        for _ in 0..<20 {
            XCTAssertNotEqual(MorningReminders.randomReminder(excluding: pool[0]), pool[0])
        }
    }

    func test_randomReminder_returns_sole_entry_when_pool_has_one() throws {
        let only = Reminder(text: "only")
        try writeReminders([only])
        XCTAssertEqual(MorningReminders.randomReminder(excluding: only), only)
    }

    // MARK: - installSeed()

    func test_installSeed_creates_empty_file_once() throws {
        MorningReminders.installSeed()
        let url = MorningReminders.customFileURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(MorningReminders.todays())
    }

    func test_installSeed_never_overwrites_existing_content() throws {
        try writeReminders([Reminder(text: "keep me")])
        MorningReminders.installSeed()
        XCTAssertEqual(MorningReminders.todays()?.text, "keep me")
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return Calendar.current.date(from: comps)!
    }
}
