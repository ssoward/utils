import XCTest
@testable import BrotherPaul

/// Sentinel: confirms the test target compiles and links the executable target,
/// and that `@testable import BrotherPaul` reaches internal symbols.
final class HarnessSmokeTest: XCTestCase {

    func test_test_target_is_wired() {
        XCTAssertTrue(true)
    }

    func test_can_reach_internal_symbols() {
        // AppConfig.default is internal; if we can reference it the bridge works.
        let modes = AppConfig.default.modes
        XCTAssertFalse(modes.isEmpty)
    }
}
