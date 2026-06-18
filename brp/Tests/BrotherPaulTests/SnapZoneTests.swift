import XCTest
@testable import BrotherPaul

final class SnapZoneTests: XCTestCase {

    /// A canonical 1920×1080 visible frame at origin (0,0) for frame() tests.
    private let visible = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    // MARK: - frame(inVisibleFrame:)

    func test_leftHalf_frame() {
        XCTAssertEqual(SnapZone.leftHalf.frame(inVisibleFrame: visible),
                       CGRect(x: 0, y: 0, width: 960, height: 1080))
    }

    func test_rightHalf_frame() {
        XCTAssertEqual(SnapZone.rightHalf.frame(inVisibleFrame: visible),
                       CGRect(x: 960, y: 0, width: 960, height: 1080))
    }

    func test_topLeftQuarter_frame() {
        XCTAssertEqual(SnapZone.topLeftQuarter.frame(inVisibleFrame: visible),
                       CGRect(x: 0, y: 540, width: 960, height: 540))
    }

    func test_maximize_frame() {
        XCTAssertEqual(SnapZone.maximize.frame(inVisibleFrame: visible), visible)
    }

    func test_center_frame_is_60_by_70_percent_centered() {
        let f = SnapZone.center.frame(inVisibleFrame: visible)
        XCTAssertEqual(f.width, 1152, accuracy: 0.01)
        XCTAssertEqual(f.height, 756, accuracy: 0.01)
        XCTAssertEqual(f.midX, visible.midX, accuracy: 0.01)
        XCTAssertEqual(f.midY, visible.midY, accuracy: 0.01)
    }

    func test_frame_respects_nonzero_origin() {
        // Second monitor at (1920, 0), same size.
        let offset = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(SnapZone.leftHalf.frame(inVisibleFrame: offset),
                       CGRect(x: 1920, y: 0, width: 960, height: 1080))
    }

    // MARK: - zoneForCursor(_:screenFrame:)

    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func test_cursor_in_corner_picks_quadrant() {
        XCTAssertEqual(SnapZone.zoneForCursor(CGPoint(x: 5, y: 1075),
                                              screenFrame: screen),
                       .topLeftQuarter)
        XCTAssertEqual(SnapZone.zoneForCursor(CGPoint(x: 1915, y: 1075),
                                              screenFrame: screen),
                       .topRightQuarter)
        XCTAssertEqual(SnapZone.zoneForCursor(CGPoint(x: 5, y: 5),
                                              screenFrame: screen),
                       .bottomLeftQuarter)
        XCTAssertEqual(SnapZone.zoneForCursor(CGPoint(x: 1915, y: 5),
                                              screenFrame: screen),
                       .bottomRightQuarter)
    }

    func test_cursor_against_top_edge_picks_maximize() {
        XCTAssertEqual(SnapZone.zoneForCursor(CGPoint(x: 800, y: 1080),
                                              screenFrame: screen),
                       .maximize)
    }

    func test_cursor_against_left_edge_picks_leftHalf() {
        XCTAssertEqual(SnapZone.zoneForCursor(CGPoint(x: 0, y: 540),
                                              screenFrame: screen),
                       .leftHalf)
    }

    func test_cursor_in_middle_returns_nil() {
        XCTAssertNil(SnapZone.zoneForCursor(CGPoint(x: 800, y: 500),
                                             screenFrame: screen))
    }
}
