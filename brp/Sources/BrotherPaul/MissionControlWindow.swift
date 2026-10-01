import AppKit
import SwiftUI

@MainActor
final class MissionControlWindow {

    private let coordinator = MissionControlCoordinator()
    private var window: NSWindow?
    private var autoRefreshTimer: Timer?
    private var closeObserver: NSObjectProtocol?

    /// Show (or front-bring) the Mission Control window and kick off a refresh.
    func show() {
        if window == nil {
            let view = MissionControlView(coordinator: coordinator)
            let host = NSHostingController(rootView: view)
            let w = KeyboardCloseWindow(contentViewController: host)
            w.title = "Mission Control"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 720, height: 600))
            w.center()
            w.isReleasedWhenClosed = false
            window = w

            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: w, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.stopAutoRefresh() }
            }
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        Task { await coordinator.refresh() }
        startAutoRefresh()
    }

    /// Keep the digest fresh while the window is open, so a window left up all
    /// day doesn't show this morning's email and meetings. Todos refresh on
    /// their own (TodoMonitor); this covers the other sources.
    private func startAutoRefresh() {
        stopAutoRefresh()
        let minutes = ConfigManager.shared.config.missionControl.autoRefreshMinutes
        guard minutes > 0 else { return }
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.window?.isVisible == true, !self.coordinator.isLoading else { return }
                await self.coordinator.refresh()
            }
        }
    }

    private func stopAutoRefresh() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
    }
}
