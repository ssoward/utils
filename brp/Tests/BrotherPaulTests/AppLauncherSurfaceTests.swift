import XCTest
@testable import BrotherPaul

final class AppLauncherSurfaceTests: XCTestCase {
    // Launching/quitting real apps can't run headless; this only guards the
    // public surface so executors (Task 9–10) can compile against it.
    func testQuitUnknownAppReturnsFalse() {
        XCTAssertFalse(AppLauncher.quitApp(named: "NoSuchApp_ZZZ_12345"))
    }
}
