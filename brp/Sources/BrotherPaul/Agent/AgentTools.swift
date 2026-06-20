// brp/Sources/BrotherPaul/Agent/AgentTools.swift
import Foundation

enum AgentTools {

    static let systemPrompt = """
    You are Brother Paul, a concise, friendly macOS work assistant. You can open and \
    close apps, start and end work-session modes, snap windows, answer questions about \
    the user's calendar and email, and run system actions. Prefer the most specific \
    tool. Keep spoken replies short — one or two sentences. Only call a tool when the \
    user clearly wants an action or current information; otherwise just answer.
    """

    static func definitions() -> [APIToolDefinition] {
        [
            APIToolDefinition(
                name: "control_apps",
                description: "Open or close an app, or start/end a work-session mode. Use when the user wants to launch, quit, or switch their work environment.",
                input_schema: objectSchema(
                    properties: [
                        "action": stringEnum(["open_app", "close_app", "start_mode", "end_mode", "hide_others"], "What to do."),
                        "app": stringProp("App name, for open_app/close_app (e.g. 'Slack')."),
                        "mode": stringProp("Mode name, for start_mode/end_mode (e.g. 'Deep Work').")
                    ],
                    required: ["action"])),

            APIToolDefinition(
                name: "control_windows",
                description: "Snap the focused window (or a named app's window) to a screen zone.",
                input_schema: objectSchema(
                    properties: [
                        "zone": stringEnum(SnapZone.allCases.map(\.rawValue), "Target zone."),
                        "app": stringProp("Optional app to focus first.")
                    ],
                    required: ["zone"])),

            APIToolDefinition(
                name: "query_schedule",
                description: "Read the user's upcoming calendar events, priority email, and recent notifications. Use to answer questions about their day.",
                input_schema: objectSchema(
                    properties: [
                        "sources": .object([
                            "type": .string("array"),
                            "items": .object(["type": .string("string")]),
                            "description": .string("Subset of ['calendar','email','notifications']. Omit for calendar+email.")
                        ])
                    ],
                    required: [])),

            APIToolDefinition(
                name: "run_system_action",
                description: "Open a URL or file, or run an AppleScript or shell command. Use only when no more specific tool fits.",
                input_schema: objectSchema(
                    properties: [
                        "kind": stringEnum(["open_url", "open_file", "applescript", "shell"], "Action kind."),
                        "payload": stringProp("URL, file path, AppleScript source, or shell command.")
                    ],
                    required: ["kind", "payload"]))
        ]
    }

    // MARK: - schema helpers

    private static func objectSchema(properties: [String: JSONValue], required: [String]) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map { .string($0) })
        ])
    }
    private static func stringProp(_ description: String) -> JSONValue {
        .object(["type": .string("string"), "description": .string(description)])
    }
    private static func stringEnum(_ values: [String], _ description: String) -> JSONValue {
        .object([
            "type": .string("string"),
            "enum": .array(values.map { .string($0) }),
            "description": .string(description)
        ])
    }
}

/// Routes a ToolCall to the executor that handles its tool name.
final class AgentToolRegistry {
    private let allowSystemControl: Bool
    init(allowSystemControl: Bool) { self.allowSystemControl = allowSystemControl }

    @MainActor
    func dispatch(_ call: ToolCall) async -> ExecutionOutcome {
        switch call.name {
        case "control_apps":       return await AppControlExecutor().execute(call)
        case "control_windows":    return await WindowControlExecutor().execute(call)
        case "query_schedule":     return await ScheduleQueryExecutor().execute(call)
        case "run_system_action":  return await SystemControlExecutor(allowSystemControl: allowSystemControl).execute(call)
        default:                   return .failure("Unknown tool: \(call.name).")
        }
    }
}
