// brp/Sources/BrotherPaul/Agent/SystemControlExecutor.swift
import AppKit

struct SystemControlExecutor: ToolExecutor {
    let allowSystemControl: Bool

    @MainActor
    func execute(_ call: ToolCall) async -> ExecutionOutcome {
        guard allowSystemControl else {
            return .failure("System control is disabled in Brother Paul's settings.")
        }
        guard let payload = call.input["payload"]?.stringValue else { return .failure("Missing 'payload'.") }

        switch call.input["kind"]?.stringValue {
        case "open_url":
            guard let url = URL(string: payload) else { return .failure("Invalid URL.") }
            NSWorkspace.shared.open(url)
            return .ok("Opened \(payload).")

        case "open_file":
            NSWorkspace.shared.open(URL(fileURLWithPath: (payload as NSString).expandingTildeInPath))
            return .ok("Opened \(payload).")

        case "applescript":
            var error: NSDictionary?
            let script = NSAppleScript(source: payload)
            let result = script?.executeAndReturnError(&error)
            if let error = error { return .failure("AppleScript error: \(error)") }
            return .ok(result?.stringValue ?? "Ran the AppleScript.")

        case "shell":
            return runShell(payload)

        default:
            return .failure("Unknown run_system_action kind.")
        }
    }

    private func runShell(_ command: String) -> ExecutionOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return process.terminationStatus == 0
                ? .ok(output.isEmpty ? "Done." : output)
                : .failure("Command exited \(process.terminationStatus): \(output)")
        } catch {
            return .failure("Couldn't run the command: \(error.localizedDescription)")
        }
    }
}
