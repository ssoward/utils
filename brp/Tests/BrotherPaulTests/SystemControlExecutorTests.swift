// brp/Tests/BrotherPaulTests/SystemControlExecutorTests.swift
import XCTest
@testable import BrotherPaul

final class SystemControlExecutorTests: XCTestCase {

    @MainActor
    func testDisallowedWhenSystemControlOff() async {
        var cfg = VoiceConfig.default
        cfg.allowSystemControl = false
        let exec = SystemControlExecutor(allowSystemControl: cfg.allowSystemControl)
        let outcome = await exec.execute(ToolCall(id: "1", name: "run_system_action",
            input: ["kind": .string("open_url"), "payload": .string("https://x.com")]))
        XCTAssertTrue(outcome.isError)
        XCTAssertTrue(outcome.content.lowercased().contains("disabled"))
    }

    @MainActor
    func testUnknownKindIsError() async {
        let exec = SystemControlExecutor(allowSystemControl: true)
        let outcome = await exec.execute(ToolCall(id: "1", name: "run_system_action",
            input: ["kind": .string("teleport"), "payload": .string("x")]))
        XCTAssertTrue(outcome.isError)
    }

    @MainActor
    func testShellRunsAndCapturesOutput() async {
        let exec = SystemControlExecutor(allowSystemControl: true)
        let outcome = await exec.execute(ToolCall(id: "1", name: "run_system_action",
            input: ["kind": .string("shell"), "payload": .string("echo hello-brp")]))
        XCTAssertFalse(outcome.isError)
        XCTAssertTrue(outcome.content.contains("hello-brp"))
    }
}
