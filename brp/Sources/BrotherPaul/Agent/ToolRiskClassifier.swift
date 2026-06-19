// brp/Sources/BrotherPaul/Agent/ToolRiskClassifier.swift
import Foundation

enum ToolRiskClassifier {

    /// Shell/AppleScript fragments that must always be confirmed regardless of tier.
    private static let destructivePatterns: [String] = [
        "rm -rf", "rm -r ", "rm -f", "sudo ", "mkfs", "diskutil ", "dd ", "killall",
        ":(){", "shutdown", "reboot", "> /dev/", "chmod -r", "chown -r", "fdisk"
    ]

    static func risk(for call: ToolCall) -> ToolRisk {
        switch call.name {
        case "control_apps":
            switch call.input["action"]?.stringValue {
            case "open_app", "start_mode", "hide_others": return .safe
            case "close_app", "end_mode":                  return .confirm
            default:                                       return .confirm
            }
        case "control_windows":
            return .safe
        case "query_schedule":
            return .safe
        case "run_system_action":
            if isDestructive(call) { return .confirm }
            switch call.input["kind"]?.stringValue {
            case "open_url", "open_file": return .safe
            default:                      return .confirm   // applescript, shell, setting
            }
        default:
            return .confirm
        }
    }

    /// Always-confirm deny-list: true if the payload looks destructive.
    static func isDestructive(_ call: ToolCall) -> Bool {
        guard call.name == "run_system_action",
              let payload = call.input["payload"]?.stringValue?.lowercased() else { return false }
        return destructivePatterns.contains { payload.contains($0) }
    }
}
