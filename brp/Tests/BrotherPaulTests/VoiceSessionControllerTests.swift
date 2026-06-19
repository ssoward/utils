// brp/Tests/BrotherPaulTests/VoiceSessionControllerTests.swift
import XCTest
@testable import BrotherPaul

@MainActor
final class VoiceSessionControllerTests: XCTestCase {

    // MARK: - Mocks

    final class MockWake: WakeWordEngine {
        var onWake: (() -> Void)?
        private(set) var started = false
        func start() { started = true }
        func stop() {}
        func fire() { onWake?() }
    }

    final class MockSTT: SpeechTranscribing {
        private(set) var startCount = 0
        private(set) var stopped = false
        var onFinal: ((String) -> Void)?
        func startListening(onFinal: @escaping (String) -> Void) { startCount += 1; self.onFinal = onFinal }
        func stop() { stopped = true }
    }

    final class MockTTS: SpeechSynthesizing {
        private(set) var spoken: [String] = []
        func speak(_ text: String) { spoken.append(text) }
        func stop() {}
    }

    final class MockRegistry: ToolDispatching {
        private(set) var dispatched: [String] = []
        func dispatch(_ call: ToolCall) async -> ExecutionOutcome { dispatched.append(call.name); return .ok("did \(call.name)") }
    }

    final class MockUI: VoiceUI {
        private(set) var states: [VoiceUIState] = []
        var confirmResult = true
        private(set) var confirmAsks = 0
        func show(_ state: VoiceUIState) { states.append(state) }
        func requestConfirmation(_ call: ToolCall) async -> Bool { confirmAsks += 1; return confirmResult }
    }

    /// A brain that returns a canned reply, optionally exercising confirm/execute
    /// with a scripted tool call first (simulating ClaudeClient's loop).
    final class MockBrain: AgentBrain {
        var reply = "All set."
        var scriptedCall: ToolCall?
        var errorToThrow: Error?
        func send(_ transcript: String,
                  confirm: @escaping (ToolCall) async -> Bool,
                  execute: @escaping (ToolCall) async -> ExecutionOutcome) async throws -> String {
            if let e = errorToThrow { throw e }
            if let call = scriptedCall {
                if await confirm(call) { _ = await execute(call) }
            }
            return reply
        }
    }

    private func makeController(
        wake: MockWake? = nil, stt: MockSTT? = nil, tts: MockTTS? = nil,
        brain: MockBrain? = nil, registry: MockRegistry? = nil,
        ui: MockUI? = nil, speakReplies: Bool = true
    ) -> (VoiceSessionController, MockWake, MockSTT, MockTTS, MockBrain, MockRegistry, MockUI) {
        let w = wake ?? MockWake()
        let s = stt ?? MockSTT()
        let t = tts ?? MockTTS()
        let b = brain ?? MockBrain()
        let r = registry ?? MockRegistry()
        let u = ui ?? MockUI()
        let c = VoiceSessionController(wake: w, transcriber: s, synthesizer: t,
                                       brain: b, registry: r, ui: u, speakReplies: speakReplies)
        return (c, w, s, t, b, r, u)
    }

    // MARK: - Tests

    func testWakeBeginsListening() async {
        let (c, wake, stt, _, _, _, ui) = makeController()
        c.start()
        XCTAssertTrue(wake.started)
        wake.fire()
        await Task.yield()
        XCTAssertEqual(c.state, .listening)
        XCTAssertEqual(stt.startCount, 1)
        XCTAssertEqual(ui.states.last, .listening)
    }

    func testEmptyTranscriptRepromptsAndReturnsToIdle() async {
        let (c, _, stt, tts, _, _, _) = makeController()
        c.start()
        await c.handleFinalTranscript("   ")
        XCTAssertTrue(stt.stopped)
        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(tts.spoken.count, 1)
        XCTAssertTrue(tts.spoken[0].lowercased().contains("didn't catch"))
    }

    func testSimpleReplyIsSpokenAndShown() async {
        let brain = MockBrain(); brain.reply = "Your next meeting is at 2."
        let (c, _, _, tts, _, _, ui) = makeController(brain: brain)
        await c.handleFinalTranscript("what's next?")
        XCTAssertEqual(tts.spoken, ["Your next meeting is at 2."])
        XCTAssertEqual(ui.states.last, .idle)
        XCTAssertTrue(ui.states.contains(.replied("Your next meeting is at 2.")))
        XCTAssertEqual(c.state, .idle)
    }

    func testApprovedConfirmationExecutesTool() async {
        let brain = MockBrain()
        brain.scriptedCall = ToolCall(id: "1", name: "control_apps",
                                      input: ["action": .string("close_app"), "app": .string("Slack")])
        let ui = MockUI(); ui.confirmResult = true
        let registry = MockRegistry()
        let (c, _, _, _, _, _, _) = makeController(brain: brain, registry: registry, ui: ui)
        await c.handleFinalTranscript("close slack")
        XCTAssertEqual(ui.confirmAsks, 1)
        XCTAssertEqual(registry.dispatched, ["control_apps"])
    }

    func testDeniedConfirmationSkipsExecution() async {
        let brain = MockBrain()
        brain.scriptedCall = ToolCall(id: "1", name: "control_apps",
                                      input: ["action": .string("close_app"), "app": .string("Slack")])
        let ui = MockUI(); ui.confirmResult = false
        let registry = MockRegistry()
        let (c, _, _, _, _, _, _) = makeController(brain: brain, registry: registry, ui: ui)
        await c.handleFinalTranscript("close slack")
        XCTAssertEqual(ui.confirmAsks, 1)
        XCTAssertTrue(registry.dispatched.isEmpty)
    }

    func testBrainErrorIsSpokenAndReturnsToIdle() async {
        let brain = MockBrain(); brain.errorToThrow = ClaudeClientError.missingAPIKey
        let (c, _, _, tts, _, _, ui) = makeController(brain: brain)
        await c.handleFinalTranscript("hello")
        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(tts.spoken.count, 1)
        if case .error = ui.states.last {} else { XCTFail("expected error state") }
    }

    func testSpeakRepliesFalseStaysSilent() async {
        let brain = MockBrain(); brain.reply = "Done."
        let (c, _, _, tts, _, _, _) = makeController(brain: brain, speakReplies: false)
        await c.handleFinalTranscript("do it")
        XCTAssertTrue(tts.spoken.isEmpty)
        XCTAssertEqual(c.state, .idle)
    }

    func testBrainErrorIsSilentWhenSpeakRepliesFalse() async {
        let brain = MockBrain(); brain.errorToThrow = ClaudeClientError.missingAPIKey
        let (c, _, _, tts, _, _, _) = makeController(brain: brain, speakReplies: false)
        await c.handleFinalTranscript("hello")
        XCTAssertTrue(tts.spoken.isEmpty)
        XCTAssertEqual(c.state, .idle)
    }
}
