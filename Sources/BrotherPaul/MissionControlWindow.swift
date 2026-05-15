import AppKit
import SwiftUI

@MainActor
final class MissionControlWindow {

    private let coordinator = MissionControlCoordinator()
    private var window: NSWindow?

    /// Show (or front-bring) the Mission Control window and kick off a refresh.
    func show() {
        if window == nil {
            let view = MissionControlView(coordinator: coordinator)
            let host = NSHostingController(rootView: view)
            let w = NSWindow(contentViewController: host)
            w.title = "Mission Control"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 720, height: 600))
            w.center()
            w.isReleasedWhenClosed = false
            window = w
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        Task { await coordinator.refresh() }
    }
}
