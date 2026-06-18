import XCTest
@testable import BrotherPaul

final class VIPMatcherTests: XCTestCase {

    func test_no_vip_senders_means_never_matches() {
        XCTAssertFalse(VIPMatcher.isVIP(haystacks: ["boss@example.com"], vipSenders: []))
    }

    func test_substring_match_is_case_insensitive() {
        XCTAssertTrue(VIPMatcher.isVIP(
            haystacks: ["Boss Person <boss@Example.com>"],
            vipSenders: ["boss@example.com"]
        ))
    }

    func test_partial_match_against_display_name() {
        XCTAssertTrue(VIPMatcher.isVIP(
            haystacks: ["Alice Smith <alice@x.com>"],
            vipSenders: ["alice smith"]
        ))
    }

    func test_no_match_when_neither_field_contains_vip() {
        XCTAssertFalse(VIPMatcher.isVIP(
            haystacks: ["junk@example.com"],
            vipSenders: ["boss@example.com"]
        ))
    }

    func test_empty_vip_string_is_skipped_not_a_wildcard() {
        XCTAssertFalse(VIPMatcher.isVIP(
            haystacks: ["anything"],
            vipSenders: [""]
        ))
    }

    func test_matches_any_of_multiple_haystacks() {
        XCTAssertTrue(VIPMatcher.isVIP(
            haystacks: ["random sender", "Re: from the CEO"],
            vipSenders: ["ceo"]
        ))
    }

    func test_matches_any_of_multiple_vip_entries() {
        XCTAssertTrue(VIPMatcher.isVIP(
            haystacks: ["alice@x.com"],
            vipSenders: ["bob@x.com", "alice@x.com"]
        ))
    }
}

final class NotificationBlocklistTests: XCTestCase {

    func test_empty_blocklist_includes_everything() {
        XCTAssertTrue(NotificationBlocklist.shouldInclude(
            bundleID: "com.example.app",
            blocklist: []
        ))
    }

    func test_match_excludes() {
        XCTAssertFalse(NotificationBlocklist.shouldInclude(
            bundleID: "com.apple.systemnotifications",
            blocklist: ["com.apple.systemnotifications"]
        ))
    }

    func test_match_is_case_insensitive() {
        XCTAssertFalse(NotificationBlocklist.shouldInclude(
            bundleID: "com.apple.SystemNotifications",
            blocklist: ["COM.APPLE.systemnotifications"]
        ))
    }

    func test_match_is_exact_bundle_id_not_substring() {
        // "apple" is a substring of "com.apple.X" but blocklist is exact match.
        XCTAssertTrue(NotificationBlocklist.shouldInclude(
            bundleID: "com.apple.mail",
            blocklist: ["apple"]
        ))
    }

    func test_non_matching_bundle_is_included() {
        XCTAssertTrue(NotificationBlocklist.shouldInclude(
            bundleID: "com.example.app",
            blocklist: ["com.apple.systemnotifications", "com.other.thing"]
        ))
    }
}
