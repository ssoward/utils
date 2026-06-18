// brp/Tests/BrotherPaulTests/ClaudeClientTests.swift
import XCTest
@testable import BrotherPaul

private final class StubTransport: MessagesTransport {
    var responses: [MessagesResponse]
    private(set) var requestCount = 0
    init(_ responses: [MessagesResponse]) { self.responses = responses }
    func send(_ request: MessagesRequest) async throws -> MessagesResponse {
        defer { requestCount += 1 }
        return responses[requestCount]
    }
}

final class ClaudeClientTests: XCTestCase {

    private func makeClient(_ transport: MessagesTransport) -> ClaudeClient {
        let secrets = InMemorySecretStore()
        secrets.set("sk-ant-test", for: SecretKey.anthropicAPIKey)
        return ClaudeClient(config: .default, tools: [], systemPrompt: "sys",
                            secrets: secrets, transport: transport)
    }

    func testReturnsFinalTextWhenNoTools() async throws {
        let transport = StubTransport([
            MessagesResponse(content: [.text("Your next meeting is at 2pm.")], stop_reason: "end_turn")
        ])
        let client = makeClient(transport)
        let reply = try await client.send("what's next?",
            confirm: { _ in true }, execute: { _ in .ok("") })
        XCTAssertEqual(reply, "Your next meeting is at 2pm.")
    }

    func testExecutesSafeToolThenReturnsText() async throws {
        let transport = StubTransport([
            MessagesResponse(content: [
                .toolUse(id: "tu1", name: "control_windows", input: ["zone": .string("leftHalf")])
            ], stop_reason: "tool_use"),
            MessagesResponse(content: [.text("Done.")], stop_reason: "end_turn")
        ])
        let client = makeClient(transport)
        var confirmCalled = false
        var executed: [String] = []
        let reply = try await client.send("snap left",
            confirm: { _ in confirmCalled = true; return true },
            execute: { call in executed.append(call.name); return .ok("snapped") })
        XCTAssertEqual(reply, "Done.")
        XCTAssertFalse(confirmCalled)          // safe tool: no confirmation
        XCTAssertEqual(executed, ["control_windows"])
    }

    func testRiskyToolAsksConfirmationAndSkipsWhenDenied() async throws {
        let transport = StubTransport([
            MessagesResponse(content: [
                .toolUse(id: "tu1", name: "control_apps",
                         input: ["action": .string("close_app"), "app": .string("Slack")])
            ], stop_reason: "tool_use"),
            MessagesResponse(content: [.text("Okay, I left it open.")], stop_reason: "end_turn")
        ])
        let client = makeClient(transport)
        var executed = false
        let reply = try await client.send("close slack",
            confirm: { _ in false },                    // user denies
            execute: { _ in executed = true; return .ok("") })
        XCTAssertFalse(executed)                          // denied → not executed
        XCTAssertEqual(reply, "Okay, I left it open.")
    }

    func testMissingKeyThrows() async {
        let secrets = InMemorySecretStore()       // no key set
        let client = ClaudeClient(config: .default, tools: [], systemPrompt: "s",
                                  secrets: secrets, transport: StubTransport([]))
        do {
            _ = try await client.send("hi", confirm: { _ in true }, execute: { _ in .ok("") })
            XCTFail("expected missingAPIKey")
        } catch ClaudeClientError.missingAPIKey {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testRefusalThrows() async {
        let transport = StubTransport([MessagesResponse(content: [], stop_reason: "refusal")])
        let client = makeClient(transport)
        do {
            _ = try await client.send("hi", confirm: { _ in true }, execute: { _ in .ok("") })
            XCTFail("expected refused")
        } catch ClaudeClientError.refused {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testToolUseWithEndTurnStillExecutes() async throws {
        let transport = StubTransport([
            MessagesResponse(content: [
                .toolUse(id: "tu1", name: "control_windows", input: ["zone": .string("leftHalf")])
            ], stop_reason: "end_turn"),                       // unusual: tool_use + end_turn
            MessagesResponse(content: [.text("Done.")], stop_reason: "end_turn")
        ])
        let client = makeClient(transport)
        var executed = false
        let reply = try await client.send("snap left",
            confirm: { _ in true },
            execute: { _ in executed = true; return .ok("snapped") })
        XCTAssertTrue(executed)                                // tool NOT dropped
        XCTAssertEqual(reply, "Done.")
    }
}
