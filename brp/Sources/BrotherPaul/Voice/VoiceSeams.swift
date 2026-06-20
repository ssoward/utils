// brp/Sources/BrotherPaul/Voice/VoiceSeams.swift
import Foundation

/// Continuously listens for the wake word and fires `onWake`. Implemented by
/// Porcupine (or the hotkey fallback) in Plan 2b.
protocol WakeWordEngine: AnyObject {
    var onWake: (() -> Void)? { get set }
    func start()
    func stop()
}

/// Captures the user's spoken request and reports the final transcript.
/// Implemented by SFSpeechRecognizer in Plan 2b.
@MainActor
protocol SpeechTranscribing: AnyObject {
    func startListening(onFinal: @escaping (String) -> Void)
    func stop()
}

/// Speaks replies aloud. Implemented by AVSpeechSynthesizer in Plan 2b.
@MainActor
protocol SpeechSynthesizing: AnyObject {
    func speak(_ text: String)
    func stop()
}

/// Executes a tool call. AgentToolRegistry conforms.
@MainActor
protocol ToolDispatching: AnyObject {
    func dispatch(_ call: ToolCall) async -> ExecutionOutcome
}

/// The conversational brain. ClaudeClient conforms.
protocol AgentBrain: AnyObject {
    func send(_ transcript: String,
              confirm: @escaping (ToolCall) async -> Bool,
              execute: @escaping (ToolCall) async -> ExecutionOutcome) async throws -> String
}

/// What the floating panel renders. Implemented by the SwiftUI panel in Plan 2b.
enum VoiceUIState: Equatable {
    case idle
    case listening
    case thinking(String)        // the heard transcript
    case confirming(ToolCall)    // a risky action awaiting yes/no
    case replied(String)         // the spoken reply, shown as text
    case error(String)
}

@MainActor
protocol VoiceUI: AnyObject {
    func show(_ state: VoiceUIState)
    /// Ask the user to approve a risky action (spoken "yes"/"no" or a panel button).
    func requestConfirmation(_ call: ToolCall) async -> Bool
}

extension ClaudeClient: AgentBrain {}
extension AgentToolRegistry: ToolDispatching {}
