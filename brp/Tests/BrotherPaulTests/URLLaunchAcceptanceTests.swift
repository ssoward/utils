import XCTest
@testable import BrotherPaul

/// Acceptance-level smoke test: drives the real AppDelegate URL-handling path
/// (`brotherpaul://start` / `stop`) end-to-end and asserts the correct session
/// intent reaches AppLauncher — without launching or quitting any real apps.
/// AppLauncher.sessionSink intercepts the side effects.
@MainActor
final class URLLaunchAcceptanceTests: XCTestCase {

    private var launched: [(verb: String, mode: String)] = []
    private var delegate: AppDelegate!
    private var tmp: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Isolate config in a temp dir so we're not affected by other suites
        // that mutate the shared singleton (e.g. ConfigManagerTests). Bootstrap
        // writes & loads AppConfig.default, giving us the stock "Full"/"Deep Work" modes.
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("brpaul-acc-\(UUID().uuidString)", isDirectory: true)
        setenv("BROTHERPAUL_CONFIG_DIR", tmp.path, 1)
        ConfigManager.shared.bootstrap()

        launched = []
        AppLauncher.sessionSink = { [weak self] verb, mode in
            self?.launched.append((verb, mode.name))
        }
        delegate = AppDelegate()
    }

    override func tearDownWithError() throws {
        AppLauncher.sessionSink = nil
        delegate = nil
        unsetenv("BROTHERPAUL_CONFIG_DIR")
        try? FileManager.default.removeItem(at: tmp)
        try super.tearDownWithError()
    }

    func test_start_url_with_mode_launches_that_mode() {
        delegate.handle(urlString: "brotherpaul://start?mode=Deep%20Work")
        XCTAssertEqual(launched.count, 1)
        XCTAssertEqual(launched.first?.verb, "started")
        XCTAssertEqual(launched.first?.mode, "Deep Work")
    }

    func test_start_url_without_mode_launches_default_mode() {
        delegate.handle(urlString: "brotherpaul://start")
        XCTAssertEqual(launched.first?.verb, "started")
        // AppConfig.default.defaultMode == "Full"
        XCTAssertEqual(launched.first?.mode, "Full")
    }

    func test_stop_url_ends_the_session() {
        delegate.handle(urlString: "brotherpaul://stop?mode=Full")
        XCTAssertEqual(launched.count, 1)
        XCTAssertEqual(launched.first?.verb, "ended")
        XCTAssertEqual(launched.first?.mode, "Full")
    }

    func test_unknown_mode_does_not_launch_anything() {
        delegate.handle(urlString: "brotherpaul://start?mode=NoSuchMode")
        XCTAssertTrue(launched.isEmpty)
    }

    func test_unparseable_url_is_ignored() {
        delegate.handle(urlString: "not a url at all")
        XCTAssertTrue(launched.isEmpty)
    }
}
