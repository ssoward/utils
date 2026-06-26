import XCTest
@testable import BrotherPaul

/// Pure parsers extracted from GmailFetcher, exercised against captured
/// Gmail REST payloads (no network).
final class GmailParserTests: XCTestCase {

    private func data(_ s: String) -> Data { Data(s.utf8) }

    // MARK: - parseAccessToken

    func test_parseAccessToken_extracts_token() throws {
        let token = try GmailFetcher.parseAccessToken(data(#"{"access_token":"ya29.abc","expires_in":3599}"#))
        XCTAssertEqual(token, "ya29.abc")
    }

    func test_parseAccessToken_throws_when_missing() {
        XCTAssertThrowsError(try GmailFetcher.parseAccessToken(data(#"{"error":"invalid_grant"}"#)))
    }

    func test_parseAccessToken_throws_on_garbage() {
        XCTAssertThrowsError(try GmailFetcher.parseAccessToken(data("not json")))
    }

    // MARK: - parseMessageIDs

    func test_parseMessageIDs_extracts_ids() {
        let ids = GmailFetcher.parseMessageIDs(data(#"{"messages":[{"id":"a"},{"id":"b"}]}"#))
        XCTAssertEqual(ids, ["a", "b"])
    }

    func test_parseMessageIDs_empty_when_no_messages() {
        XCTAssertEqual(GmailFetcher.parseMessageIDs(data(#"{"resultSizeEstimate":0}"#)), [])
    }

    func test_parseMessageIDs_empty_on_garbage() {
        XCTAssertEqual(GmailFetcher.parseMessageIDs(data("<<<")), [])
    }

    // MARK: - parseMessage

    private let sample = #"""
    {
      "internalDate": "1750257000000",
      "payload": {
        "headers": [
          {"name": "Subject", "value": "Quarterly review"},
          {"name": "From", "value": "Boss <boss@example.com>"},
          {"name": "Date", "value": "Wed, 18 Jun 2025 14:30:00 +0000"}
        ]
      }
    }
    """#

    func test_parseMessage_maps_headers_and_url() throws {
        let item = try XCTUnwrap(GmailFetcher.parseMessage(data(sample), id: "msg123", vipSenders: []))
        XCTAssertEqual(item.source, .gmail)
        XCTAssertEqual(item.title, "Quarterly review")
        XCTAssertEqual(item.subtitle, "Boss <boss@example.com>")
        XCTAssertEqual(item.openURL?.absoluteString, "https://mail.google.com/mail/u/0/#inbox/msg123")
        // internalDate (ms) wins over the Date header.
        XCTAssertEqual(try XCTUnwrap(item.timestamp).timeIntervalSince1970, 1_750_257_000, accuracy: 1)
    }

    func test_parseMessage_prefers_internalDate_then_falls_back_to_date_header() throws {
        let noInternal = #"{"payload":{"headers":[{"name":"Date","value":"Wed, 18 Jun 2025 14:30:00 +0000"}]}}"#
        let item = try XCTUnwrap(GmailFetcher.parseMessage(data(noInternal), id: "x", vipSenders: []))
        XCTAssertEqual(try XCTUnwrap(item.timestamp).timeIntervalSince1970, 1_750_257_000, accuracy: 1)
    }

    func test_parseMessage_vip_sender_raises_priority() throws {
        let vip = try XCTUnwrap(GmailFetcher.parseMessage(data(sample), id: "x", vipSenders: ["boss@example.com"]))
        let normal = try XCTUnwrap(GmailFetcher.parseMessage(data(sample), id: "x", vipSenders: ["someone@else.com"]))
        XCTAssertEqual(vip.priority, 90)
        XCTAssertEqual(normal.priority, 50)
    }

    func test_parseMessage_defaults_subject_when_absent() throws {
        let item = try XCTUnwrap(GmailFetcher.parseMessage(data("{}"), id: "x", vipSenders: []))
        XCTAssertEqual(item.title, "(no subject)")
        XCTAssertNil(item.timestamp)
    }
}
