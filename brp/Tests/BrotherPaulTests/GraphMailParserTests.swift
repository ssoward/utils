import XCTest
@testable import BrotherPaul

/// Pure parsers extracted from GraphMailFetcher, exercised against captured
/// Microsoft Graph `/me/messages` payloads (no network).
final class GraphMailParserTests: XCTestCase {

    private func data(_ s: String) -> Data { Data(s.utf8) }

    // MARK: - parseAccessToken

    func test_parseAccessToken_extracts_token() throws {
        let token = try GraphMailFetcher.parseAccessToken(data(#"{"access_token":"eyJ0.x","token_type":"Bearer"}"#))
        XCTAssertEqual(token, "eyJ0.x")
    }

    func test_parseAccessToken_throws_when_missing() {
        XCTAssertThrowsError(try GraphMailFetcher.parseAccessToken(data(#"{"error":"invalid_grant"}"#)))
    }

    // MARK: - parseMessages

    private let sample = #"""
    {
      "value": [
        {
          "subject": "Status update",
          "receivedDateTime": "2026-05-31T14:23:00Z",
          "webLink": "https://outlook.office365.com/mail/id1",
          "from": {"emailAddress": {"name": "Alice Boss", "address": "alice@corp.com"}}
        },
        {
          "subject": "",
          "receivedDateTime": "2026-05-31T15:00:00.123Z",
          "from": {"emailAddress": {"address": "noname@corp.com"}}
        }
      ]
    }
    """#

    func test_parseMessages_maps_all_fields() {
        let items = GraphMailFetcher.parseMessages(data(sample), vipSenders: [])
        XCTAssertEqual(items.count, 2)

        XCTAssertEqual(items[0].source, .outlook)
        XCTAssertEqual(items[0].title, "Status update")
        XCTAssertEqual(items[0].subtitle, "Alice Boss") // name preferred over address
        XCTAssertEqual(items[0].openURL?.absoluteString, "https://outlook.office365.com/mail/id1")
        XCTAssertNotNil(items[0].timestamp)
    }

    func test_parseMessages_defaults_subject_and_uses_address_when_no_name() {
        let items = GraphMailFetcher.parseMessages(data(sample), vipSenders: [])
        XCTAssertEqual(items[1].title, "(no subject)")
        XCTAssertEqual(items[1].subtitle, "noname@corp.com")
    }

    func test_parseMessages_parses_fractional_seconds_timestamp() {
        // Second message uses ".123Z" — must still parse via the fractional formatter.
        let items = GraphMailFetcher.parseMessages(data(sample), vipSenders: [])
        XCTAssertNotNil(items[1].timestamp)
    }

    func test_parseMessages_vip_matches_name_address_or_subject() {
        XCTAssertEqual(GraphMailFetcher.parseMessages(data(sample), vipSenders: ["alice@corp.com"])[0].priority, 90)
        XCTAssertEqual(GraphMailFetcher.parseMessages(data(sample), vipSenders: ["Status"])[0].priority, 90)
        XCTAssertEqual(GraphMailFetcher.parseMessages(data(sample), vipSenders: ["nobody"])[0].priority, 50)
    }

    func test_parseMessages_empty_on_garbage() {
        XCTAssertEqual(GraphMailFetcher.parseMessages(data("nope"), vipSenders: []).count, 0)
        XCTAssertEqual(GraphMailFetcher.parseMessages(data(#"{"value":[]}"#), vipSenders: []).count, 0)
    }
}
