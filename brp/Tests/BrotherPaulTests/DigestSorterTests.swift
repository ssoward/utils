import XCTest
@testable import BrotherPaul

final class DigestSorterTests: XCTestCase {

    private func item(_ title: String, priority: Int, timestamp: Date?) -> DigestItem {
        DigestItem(
            source: .outlook,
            title: title,
            subtitle: nil,
            timestamp: timestamp,
            priority: priority,
            openURL: nil
        )
    }

    func test_sorts_by_priority_descending() {
        let a = item("a", priority: 50, timestamp: nil)
        let b = item("b", priority: 90, timestamp: nil)
        let c = item("c", priority: 30, timestamp: nil)
        let sorted = DigestSorter.sort([a, b, c])
        XCTAssertEqual(sorted.map(\.title), ["b", "a", "c"])
    }

    func test_within_same_priority_sorts_by_timestamp_descending() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let older = item("older", priority: 50, timestamp: now.addingTimeInterval(-3600))
        let newer = item("newer", priority: 50, timestamp: now)
        let sorted = DigestSorter.sort([older, newer])
        XCTAssertEqual(sorted.map(\.title), ["newer", "older"])
    }

    func test_nil_timestamps_go_last_within_a_priority_band() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let dated = item("dated", priority: 50, timestamp: now)
        let undated = item("undated", priority: 50, timestamp: nil)
        let sorted = DigestSorter.sort([undated, dated])
        XCTAssertEqual(sorted.map(\.title), ["dated", "undated"])
    }

    func test_empty_input_returns_empty() {
        XCTAssertTrue(DigestSorter.sort([]).isEmpty)
    }
}
