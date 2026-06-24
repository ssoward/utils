import XCTest
@testable import BrotherPaul

final class URLActionTests: XCTestCase {

    func test_start_with_no_mode() {
        XCTAssertEqual(URLActionParser.parse("brotherpaul://start"),
                       .start(mode: nil))
    }

    func test_start_with_mode() {
        XCTAssertEqual(URLActionParser.parse("brotherpaul://start?mode=Full"),
                       .start(mode: "Full"))
    }

    func test_start_with_url_encoded_mode_name() {
        XCTAssertEqual(URLActionParser.parse("brotherpaul://start?mode=Deep%20Work"),
                       .start(mode: "Deep Work"))
    }

    func test_stop_with_mode() {
        XCTAssertEqual(URLActionParser.parse("brotherpaul://stop?mode=Meetings"),
                       .stop(mode: "Meetings"))
    }

    func test_end_alias_parses_as_stop() {
        XCTAssertEqual(URLActionParser.parse("brotherpaul://end"),
                       .stop(mode: nil))
    }

    func test_action_keyword_is_case_insensitive() {
        XCTAssertEqual(URLActionParser.parse("brotherpaul://START"),
                       .start(mode: nil))
        XCTAssertEqual(URLActionParser.parse("brotherpaul://Stop"),
                       .stop(mode: nil))
    }

    func test_mode_query_key_is_case_insensitive() {
        XCTAssertEqual(URLActionParser.parse("brotherpaul://start?Mode=Full"),
                       .start(mode: "Full"))
        XCTAssertEqual(URLActionParser.parse("brotherpaul://start?MODE=Full"),
                       .start(mode: "Full"))
    }

    func test_unknown_action_returns_unknown_case() {
        XCTAssertEqual(URLActionParser.parse("brotherpaul://reboot"),
                       .unknown(action: "reboot"))
    }

    func test_empty_string_returns_nil() {
        XCTAssertNil(URLActionParser.parse(""))
    }
}
