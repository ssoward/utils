// brp/Sources/BrotherPaul/Agent/AppControlExecutor.swift
import AppKit

protocol ToolExecutor {
    @MainActor func execute(_ call: ToolCall) async -> ExecutionOutcome
}

struct AppControlExecutor: ToolExecutor {
    @MainActor
    func execute(_ call: ToolCall) async -> ExecutionOutcome {
        let config = ConfigManager.shared.config
        switch call.input["action"]?.stringValue {
        case "open_app":
            guard let app = call.input["app"]?.stringValue else { return .failure("Missing 'app'.") }
            AppLauncher.launchApp(named: app)
            return .ok("Opened \(app).")

        case "close_app":
            guard let app = call.input["app"]?.stringValue else { return .failure("Missing 'app'.") }
            let quit = AppLauncher.quitApp(named: app)
            return .ok(quit ? "Closed \(app)." : "\(app) wasn't running.")

        case "start_mode":
            guard let name = call.input["mode"]?.stringValue else { return .failure("Missing 'mode'.") }
            guard let mode = config.mode(named: name) else { return .failure("No mode named \(name).") }
            AppLauncher.launch(mode: mode, hideOthers: config.hideOthersAfterLaunch)
            return .ok("Started the \(mode.name) session.")

        case "end_mode":
            guard let name = call.input["mode"]?.stringValue else { return .failure("Missing 'mode'.") }
            guard let mode = config.mode(named: name) else { return .failure("No mode named \(name).") }
            AppLauncher.end(mode: mode)
            return .ok("Ended the \(mode.name) session.")

        case "hide_others":
            NSApp.hideOtherApplications(nil)
            return .ok("Hid the other apps.")

        default:
            return .failure("Unknown control_apps action.")
        }
    }
}
