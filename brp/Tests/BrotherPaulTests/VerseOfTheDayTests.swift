import XCTest
@testable import BrotherPaul

final class VerseOfTheDayTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("brpaul-verses-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        setenv("BROTHERPAUL_CONFIG_DIR", tmp.path, 1)
        VerseOfTheDay.invalidateCacheForTesting()
    }

    override func tearDownWithError() throws {
        unsetenv("BROTHERPAUL_CONFIG_DIR")
        VerseOfTheDay.invalidateCacheForTesting()
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - todays(now:)

    func test_todays_is_stable_for_the_same_date() {
        let date = makeDate(year: 2026, month: 5, day: 21)
        let first = VerseOfTheDay.todays(now: date)
        let second = VerseOfTheDay.todays(now: date)
        XCTAssertEqual(first, second)
    }

    func test_todays_rotates_across_days() {
        // The default verse list has 120 entries; consecutive days must differ.
        let day1 = makeDate(year: 2026, month: 5, day: 21)
        let day2 = makeDate(year: 2026, month: 5, day: 22)
        XCTAssertNotEqual(VerseOfTheDay.todays(now: day1),
                          VerseOfTheDay.todays(now: day2))
    }

    func test_todays_wraps_modulo_pool_size() {
        // Same ordinal modulo defaultVerses.count produces the same verse.
        let n = VerseOfTheDay.defaultVerses.count
        let day1 = makeDate(year: 2026, month: 1, day: 1)
        guard let day1PlusN = Calendar.current.date(byAdding: .day, value: n, to: day1)
        else { return XCTFail("date math failed") }
        XCTAssertEqual(VerseOfTheDay.todays(now: day1),
                       VerseOfTheDay.todays(now: day1PlusN))
    }

    // MARK: - randomVerse(excluding:)

    func test_randomVerse_excludes_the_passed_verse() {
        let pinned = VerseOfTheDay.defaultVerses[0]
        for _ in 0..<20 {
            let pick = VerseOfTheDay.randomVerse(excluding: pinned)
            XCTAssertNotEqual(pick, pinned)
        }
    }

    func test_randomVerse_with_nil_excluding_returns_some_verse() {
        let pick = VerseOfTheDay.randomVerse(excluding: nil)
        XCTAssertTrue(VerseOfTheDay.defaultVerses.contains(pick))
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
