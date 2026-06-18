// brp/Sources/BrotherPaul/Agent/AgentTypes.swift
import Foundation

/// A single tool invocation requested by Claude.
struct ToolCall: Equatable {
    let id: String              // the tool_use block id, echoed back in tool_result
    let name: String
    let input: [String: JSONValue]
}

/// The result of executing one tool, fed back to Claude as a tool_result.
struct ExecutionOutcome: Equatable {
    let content: String
    let isError: Bool

    static func ok(_ content: String) -> ExecutionOutcome { .init(content: content, isError: false) }
    static func failure(_ message: String) -> ExecutionOutcome { .init(content: message, isError: true) }
}

/// Confirmation tier for a tool call.
enum ToolRisk: Equatable {
    case safe       // run immediately
    case confirm    // require confirmation first
}
