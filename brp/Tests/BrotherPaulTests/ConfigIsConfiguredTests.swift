import XCTest
@testable import BrotherPaul

/// `isConfigured` gates whether the Gmail / Graph fetchers run at all, so the
/// exact "which fields are required" logic is worth pinning down.
final class ConfigIsConfiguredTests: XCTestCase {

    // MARK: - GmailConfig

    func test_gmail_requires_clientID_secret_and_refreshToken() {
        XCTAssertTrue(GmailConfig(clientID: "id", clientSecret: "secret", refreshToken: "rt").isConfigured)
    }

    func test_gmail_default_is_not_configured() {
        XCTAssertFalse(GmailConfig().isConfigured)
    }

    func test_gmail_missing_any_single_field_is_not_configured() {
        XCTAssertFalse(GmailConfig(clientID: "", clientSecret: "s", refreshToken: "r").isConfigured)
        XCTAssertFalse(GmailConfig(clientID: "i", clientSecret: "", refreshToken: "r").isConfigured)
        XCTAssertFalse(GmailConfig(clientID: "i", clientSecret: "s", refreshToken: "").isConfigured)
    }

    // MARK: - GraphConfig

    func test_graph_requires_clientID_and_refreshToken_only() {
        // tenant defaults to "common" and is NOT required.
        XCTAssertTrue(GraphConfig(clientID: "id", refreshToken: "rt").isConfigured)
    }

    func test_graph_default_is_not_configured() {
        XCTAssertFalse(GraphConfig().isConfigured)
    }

    func test_graph_missing_clientID_or_refreshToken_is_not_configured() {
        XCTAssertFalse(GraphConfig(clientID: "", refreshToken: "rt").isConfigured)
        XCTAssertFalse(GraphConfig(clientID: "id", refreshToken: "").isConfigured)
    }
}
