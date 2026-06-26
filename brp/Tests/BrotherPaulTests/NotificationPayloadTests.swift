import XCTest
@testable import BrotherPaul

/// `NotificationsFetcher.parsePayload` decodes Cocoa notification plists whose
/// key schema varies across macOS versions (titl/subt/body vs.
/// title/subtitle/informativeText) and may nest fields under `req`.
final class NotificationPayloadTests: XCTestCase {

    private func plist(_ dict: [String: Any]) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
    }

    func test_parses_recent_macos_keys() {
        let p = NotificationsFetcher.parsePayload(plist(["titl": "Hi", "subt": "Sub", "body": "Body"]))
        XCTAssertEqual(p?.title, "Hi")
        XCTAssertEqual(p?.subtitle, "Sub")
        XCTAssertEqual(p?.body, "Body")
    }

    func test_parses_older_macos_keys() {
        let p = NotificationsFetcher.parsePayload(
            plist(["title": "Hi", "subtitle": "Sub", "informativeText": "Body"]))
        XCTAssertEqual(p?.title, "Hi")
        XCTAssertEqual(p?.subtitle, "Sub")
        XCTAssertEqual(p?.body, "Body")
    }

    func test_reads_fields_nested_under_req() {
        let p = NotificationsFetcher.parsePayload(plist(["req": ["titl": "Nested", "body": "B"]]))
        XCTAssertEqual(p?.title, "Nested")
        XCTAssertEqual(p?.body, "B")
    }

    func test_top_level_keys_override_req() {
        let p = NotificationsFetcher.parsePayload(
            plist(["req": ["titl": "FromReq"], "titl": "FromTop"]))
        XCTAssertEqual(p?.title, "FromTop")
    }

    func test_empty_payload_returns_nil() {
        XCTAssertNil(NotificationsFetcher.parsePayload(plist(["irrelevant": "x"])))
    }

    func test_non_plist_data_returns_nil() {
        XCTAssertNil(NotificationsFetcher.parsePayload(Data([0x00, 0x01, 0x02, 0xFF])))
    }
}
