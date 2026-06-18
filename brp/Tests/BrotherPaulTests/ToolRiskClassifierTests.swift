// brp/Tests/BrotherPaulTests/ToolRiskClassifierTests.swift
import XCTest
@testable import BrotherPaul

final class ToolRiskClassifierTests: XCTestCase {

    private func call(_ name: String, _ input: [String: JSONValue]) -> ToolCall {
        ToolCall(id: "t1", name: name, input: input)
    }

    func testOpenAppIsSafe() {
        XCTAssertEqual(ToolRiskClassifier.risk(for: call("control_apps",
            ["action": .string("open_app"), "app": .string("Slack")])), .safe)
    }

    func testStartModeIsSafe() {
        XCTAssertEqual(ToolRiskClassifier.risk(for: call("control_apps",
            ["action": .string("start_mode"), "mode": .string("Deep Work")])), .safe)
    }

    func testCloseAppRequiresConfirm() {
        XCTAssertEqual(ToolRiskClassifier.risk(for: call("control_apps",
            ["action": .string("close_app"), "app": .string("Slack")])), .confirm)
    }

    func testEndModeRequiresConfirm() {
        XCTAssertEqual(ToolRiskClassifier.risk(for: call("control_apps",
            ["action": .string("end_mode"), "mode": .string("Full")])), .confirm)
    }

    func testWindowControlIsSafe() {
        XCTAssertEqual(ToolRiskClassifier.risk(for: call("control_windows",
            ["zone": .string("leftHalf")])), .safe)
    }

    func testQueryScheduleIsSafe() {
        XCTAssertEqual(ToolRiskClassifier.risk(for: call("query_schedule", [:])), .safe)
    }

    func testOpenUrlIsSafe() {
        XCTAssertEqual(ToolRiskClassifier.risk(for: call("run_system_action",
            ["kind": .string("open_url"), "payload": .string("https://x.com")])), .safe)
    }

    func testAppleScriptRequiresConfirm() {
        XCTAssertEqual(ToolRiskClassifier.risk(for: call("run_system_action",
            ["kind": .string("applescript"), "payload": .string("tell app \"Finder\" to quit")])), .confirm)
    }

    func testShellRequiresConfirm() {
        XCTAssertEqual(ToolRiskClassifier.risk(for: call("run_system_action",
            ["kind": .string("shell"), "payload": .string("ls")])), .confirm)
    }

    func testDestructiveShellIsFlagged() {
        XCTAssertTrue(ToolRiskClassifier.isDestructive(call("run_system_action",
            ["kind": .string("shell"), "payload": .string("rm -rf ~/Documents")])))
        XCTAssertTrue(ToolRiskClassifier.isDestructive(call("run_system_action",
            ["kind": .string("shell"), "payload": .string("sudo reboot")])))
        XCTAssertFalse(ToolRiskClassifier.isDestructive(call("run_system_action",
            ["kind": .string("shell"), "payload": .string("ls -la")])))
    }

    func testUnknownToolDefaultsToConfirm() {
        XCTAssertEqual(ToolRiskClassifier.risk(for: call("something_new", [:])), .confirm)
    }

    func testOpenFileIsSafe() {
        XCTAssertEqual(ToolRiskClassifier.risk(for: call("run_system_action",
            ["kind": .string("open_file"), "payload": .string("~/notes.txt")])), .safe)
    }

    func testHideOthersIsSafe() {
        XCTAssertEqual(ToolRiskClassifier.risk(for: call("control_apps",
            ["action": .string("hide_others")])), .safe)
    }

    func testUnknownControlAppsActionRequiresConfirm() {
        XCTAssertEqual(ToolRiskClassifier.risk(for: call("control_apps",
            ["action": .string("delete_everything")])), .confirm)
    }
}
