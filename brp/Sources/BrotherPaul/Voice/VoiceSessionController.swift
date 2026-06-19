// brp/Sources/BrotherPaul/Voice/VoiceSessionController.swift
import Foundation

/// Orchestrates one voice interaction: wake → listen → think → (confirm) → speak.
/// The single stateful coordinator; all collaborators are injected protocols so
/// the state machine is fully unit-testable without hardware.
@MainActor
final class VoiceSessionController {

    enum State: Equatable { case idle, listening, thinking, confirming, speaking }

    private(set) var state: State = .idle

    private let wake: WakeWordEngine
    private let transcriber: SpeechTranscribing
    private let synthesizer: SpeechSynthesizing
    private let brain: AgentBrain
    private let registry: ToolDispatching
    private let ui: VoiceUI
    private let speakReplies: Bool

    init(wake: WakeWordEngine, transcriber: SpeechTranscribing, synthesizer: SpeechSynthesizing,
         brain: AgentBrain, registry: ToolDispatching, ui: VoiceUI, speakReplies: Bool) {
        self.wake = wake
        self.transcriber = transcriber
        self.synthesizer = synthesizer
        self.brain = brain
        self.registry = registry
        self.ui = ui
        self.speakReplies = speakReplies
    }

    /// Install the wake callback and start the engine.
    func start() {
        wake.onWake = { [weak self] in
            MainActor.assumeIsolated { self?.beginListening() }
        }
        wake.start()
    }

    func stop() {
        wake.stop()
        transcriber.stop()
        synthesizer.stop()
        state = .idle
    }

    /// Wake fired — start capturing the request (ignored unless idle).
    func beginListening() {
        guard state == .idle else { return }
        state = .listening
        ui.show(.listening)
        transcriber.startListening { [weak self] text in
            Task { @MainActor in await self?.handleFinalTranscript(text) }
        }
    }

    /// Run one full turn for a final transcript.
    func handleFinalTranscript(_ text: String) async {
        transcriber.stop()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            finish(error: "Sorry, I didn't catch that.")
            return
        }

        state = .thinking
        ui.show(.thinking(trimmed))

        do {
            let reply = try await brain.send(
                trimmed,
                confirm: { [weak self] call in
                    guard let self else { return false }
                    self.state = .confirming
                    self.ui.show(.confirming(call))
                    return await self.ui.requestConfirmation(call)
                },
                execute: { [weak self] call in
                    guard let self else { return .failure("Session ended.") }
                    return await self.registry.dispatch(call)
                })
            speakAndFinish(reply)
        } catch {
            finish(error: Self.message(for: error))
        }
    }

    // MARK: - Helpers

    private func speakAndFinish(_ reply: String) {
        state = .speaking
        ui.show(.replied(reply))
        if speakReplies, !reply.isEmpty { synthesizer.speak(reply) }
        state = .idle
        ui.show(.idle)
    }

    private func finish(error message: String) {
        if speakReplies { synthesizer.speak(message) }
        ui.show(.error(message))
        state = .idle
    }

    static func message(for error: Error) -> String {
        switch error {
        case ClaudeClientError.missingAPIKey:
            return "I don't have an API key configured yet."
        case ClaudeClientError.refused:
            return "Sorry, I can't help with that."
        case ClaudeClientError.httpError:
            return "I couldn't reach the service just now."
        default:
            return "Something went wrong handling that."
        }
    }
}
