import XCTest
@testable import BrotherPaul

final class AppConfigTests: XCTestCase {

    // MARK: - mode(named:)

    func test_mode_lookup_is_case_insensitive() {
        let config = AppConfig.default
        XCTAssertNotNil(config.mode(named: "Full"))
        XCTAssertNotNil(config.mode(named: "full"))
        XCTAssertNotNil(config.mode(named: "FULL"))
        XCTAssertNotNil(config.mode(named: "Deep Work"))
        XCTAssertNotNil(config.mode(named: "deep work"))
    }

    func test_unknown_mode_returns_nil() {
        XCTAssertNil(AppConfig.default.mode(named: "NoSuchMode"))
        XCTAssertNil(AppConfig.default.mode(named: ""))
    }

    func test_mode_lookup_returns_the_matching_mode() {
        let mode = AppConfig.default.mode(named: "Full")
        XCTAssertEqual(mode?.name, "Full")
        XCTAssertTrue(mode?.apps.contains("Microsoft Teams") ?? false)
    }

    // MARK: - JSON decoding

    func test_decodes_full_realistic_config() throws {
        let json = #"""
        {
          "hideOthersAfterLaunch": true,
          "defaultMode": "Full",
          "modes": [
            { "name": "Full",  "apps": ["TextEdit"], "urls": [] },
            { "name": "Quiet", "apps": ["Calculator"], "urls": ["https://example.com"] }
          ],
          "enableSnap": false,
          "enableDragSnap": false
        }
        """#.data(using: .utf8)!

        let cfg = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(cfg.defaultMode, "Full")
        XCTAssertEqual(cfg.modes.count, 2)
        XCTAssertFalse(cfg.enableSnap)
        XCTAssertFalse(cfg.enableDragSnap)
        XCTAssertEqual(cfg.mode(named: "Quiet")?.urls, ["https://example.com"])
    }

    func test_missing_optional_keys_fall_back_to_defaults() throws {
        // Required keys only; enableSnap/enableDragSnap/missionControl omitted.
        let json = #"""
        {
          "hideOthersAfterLaunch": false,
          "defaultMode": "Solo",
          "modes": [ { "name": "Solo", "apps": ["TextEdit"], "urls": [] } ]
        }
        """#.data(using: .utf8)!

        let cfg = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertTrue(cfg.enableSnap, "enableSnap defaults to true when missing")
        XCTAssertTrue(cfg.enableDragSnap, "enableDragSnap defaults to true when missing")
        // missionControl is initialized to its `.default`
        XCTAssertEqual(cfg.missionControl.lookbackHours, MissionControlConfig.default.lookbackHours)
    }

    func test_missing_required_key_throws() {
        // No "defaultMode".
        let json = #"""
        {
          "hideOthersAfterLaunch": false,
          "modes": []
        }
        """#.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(AppConfig.self, from: json))
    }
}
