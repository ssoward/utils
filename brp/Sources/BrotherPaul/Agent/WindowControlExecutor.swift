// brp/Sources/BrotherPaul/Agent/WindowControlExecutor.swift
import AppKit

struct WindowControlExecutor: ToolExecutor {
    @MainActor
    func execute(_ call: ToolCall) async -> ExecutionOutcome {
        guard let zoneName = call.input["zone"]?.stringValue,
              let zone = SnapZone(rawValue: zoneName) else {
            return .failure("Unknown window zone. Valid zones: \(SnapZone.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        // Optionally focus a named app first so the right window gets snapped.
        if let app = call.input["app"]?.stringValue {
            AppLauncher.launchApp(named: app)
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        let ok = WindowSnapper.snap(to: zone)
        return ok ? .ok("Snapped the window to \(zone.displayName).")
                  : .failure("Couldn't snap the window — check Accessibility permission or focus a window first.")
    }
}
