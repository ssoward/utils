// brp/Tests/BrotherPaulTests/VoiceSeamsTests.swift
import XCTest
@testable import BrotherPaul

final class VoiceSeamsTests: XCTestCase {

    @MainActor
    func testAgentToolRegistryConformsToToolDispatching() async {
        let dispatcher: ToolDispatching = AgentToolRegistry(allowSystemControl: true)
        // Unknown tool → failure, proving the protocol call routes into the registry.
        let outcome = await dispatcher.dispatch(ToolCall(id: "1", name: "nope", input: [:]))
        XCTAssertTrue(outcome.isError)
    }

    func testClaudeClientConformsToAgentBrain() {
        let secrets = InMemorySecretStore()
        let brain: AgentBrain = ClaudeClient(config: .default, tools: [], systemPrompt: "s",
                                             secrets: secrets, transport: NoopTransport())
        XCTAssertNotNil(brain)   // compile-time proof of conformance
    }

    func testVoiceUIStateEquatable() {
        XCTAssertEqual(VoiceUIState.thinking("hi"), .thinking("hi"))
        XCTAssertNotEqual(VoiceUIState.replied("a"), .replied("b"))
        XCTAssertEqual(VoiceUIState.idle, .idle)
    }
}

private final class NoopTransport: MessagesTransport {
    func send(_ request: MessagesRequest) async throws -> MessagesResponse {
        MessagesResponse(content: [], stop_reason: "end_turn")
    }
}
