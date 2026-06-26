import XCTest
@testable import BrotherPaul

/// Pure helpers inside GmailFetcher. `formEncode` builds OAuth token-exchange
/// bodies (a wrong escaping breaks auth silently) and `rfc2822Date` parses the
/// `Date:` header Gmail returns.
final class GmailFetcherHelpersTests: XCTestCase {

    // MARK: - formEncode

    func test_formEncode_single_pair() {
        XCTAssertEqual(GmailFetcher.formEncode(["grant_type": "refresh_token"]),
                       "grant_type=refresh_token")
    }

    func test_formEncode_escapes_reserved_characters() {
        // "&", "=", "+" must be percent-encoded so they don't corrupt the body.
        XCTAssertEqual(GmailFetcher.formEncode(["k": "a+b=c&d"]), "k=a%2Bb%3Dc%26d")
    }

    func test_formEncode_escapes_spaces() {
        XCTAssertEqual(GmailFetcher.formEncode(["q": "hello world"]), "q=hello%20world")
    }

    func test_formEncode_empty_is_empty_string() {
        XCTAssertEqual(GmailFetcher.formEncode([:]), "")
    }

    // MARK: - rfc2822Date

    func test_rfc2822Date_parses_valid_header() throws {
        let date = try XCTUnwrap(GmailFetcher.rfc2822Date("Wed, 18 Jun 2025 14:30:00 +0000"))
        // 2025-06-18T14:30:00Z == 1750257000 seconds since 1970.
        XCTAssertEqual(date.timeIntervalSince1970, 1_750_257_000, accuracy: 1)
    }

    func test_rfc2822Date_respects_timezone_offset() {
        let utc = GmailFetcher.rfc2822Date("Wed, 18 Jun 2025 14:30:00 +0000")
        let plusTwo = GmailFetcher.rfc2822Date("Wed, 18 Jun 2025 16:30:00 +0200")
        XCTAssertEqual(utc, plusTwo) // same instant, different wall-clock+offset
    }

    func test_rfc2822Date_rejects_garbage() {
        XCTAssertNil(GmailFetcher.rfc2822Date("not a date"))
        XCTAssertNil(GmailFetcher.rfc2822Date(""))
    }
}
