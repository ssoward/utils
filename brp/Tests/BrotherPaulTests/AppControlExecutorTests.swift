// brp/Tests/BrotherPaulTests/AppControlExecutorTests.swift
import XCTest
@testable import BrotherPaul

final class AppControlExecutorTests: XCTestCase {

    @MainActor
    func testUnknownActionIsError() async {
        let outcome = await AppControlExecutor().execute(
            ToolCall(id: "1", name: "control_apps", input: ["action": .string("frobnicate")]))
        XCTAssertTrue(outcome.isError)
    }

    @MainActor
    func testStartUnknownModeIsError() async {
        let outcome = await AppControlExecutor().execute(
            ToolCall(id: "1", name: "control_apps",
                     input: ["action": .string("start_mode"), "mode": .string("NoSuchMode_ZZZ")]))
        XCTAssertTrue(outcome.isError)
        XCTAssertTrue(outcome.content.contains("NoSuchMode_ZZZ"))
    }

    @MainActor
    func testCloseUnknownAppReportsNotRunning() async {
        let outcome = await AppControlExecutor().execute(
            ToolCall(id: "1", name: "control_apps",
                     input: ["action": .string("close_app"), "app": .string("NoSuchApp_ZZZ_12345")]))
        XCTAssertFalse(outcome.isError)          // not an error — just nothing to close
        XCTAssertTrue(outcome.content.lowercased().contains("not running")
                   || outcome.content.lowercased().contains("wasn't running"))
    }

    @MainActor
    func testWindowControlRejectsUnknownZone() async {
        let outcome = await WindowControlExecutor().execute(
            ToolCall(id: "1", name: "control_windows", input: ["zone": .string("sideways")]))
        XCTAssertTrue(outcome.isError)
    }
}
