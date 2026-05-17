import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let menuBar = MenuBarController()
    private let hotkeys = HotkeyManager()
    private let dragSnapper = DragSnapper()
    @MainActor private lazy var missionControl = MissionControlWindow()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Register before applicationDidFinishLaunching so a brotherpaul:// URL
        // that triggered a cold launch is delivered to us, not lost.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        ConfigManager.shared.bootstrap()
        VerseOfTheDay.installSeed()
        menuBar.install()
        menuBar.onConfigChanged = { [weak self] in self?.applySnapConfig() }
        menuBar.onShowMissionControl = { [weak self] in
            Task { @MainActor in self?.missionControl.show() }
        }

        applySnapConfig()

        handleLaunchArguments()
    }

    @MainActor
    func showMissionControl() {
        missionControl.show()
    }

    /// (Re-)install hotkeys and drag-snap based on current config + permission.
    func applySnapConfig() {
        let config = ConfigManager.shared.config

        if config.enableSnap, WindowSnapper.ensureAccessibility() {
            hotkeys.install()
        } else {
            hotkeys.uninstall()
        }

        if config.enableSnap, config.enableDragSnap, WindowSnapper.ensureAccessibility() {
            dragSnapper.install()
        } else {
            dragSnapper.uninstall()
        }
    }

    // MARK: - URL scheme: brotherpaul://start?mode=Deep%20Work

    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URLComponents(string: urlString) else {
            return
        }

        let action = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard action.caseInsensitiveCompare("start") == .orderedSame else {
            NSLog("BrotherPaul: ignoring URL with unknown action '%@'", action)
            return
        }

        let modeFromQuery = url.queryItems?.first(where: { $0.name.caseInsensitiveCompare("mode") == .orderedSame })?.value
        launch(modeName: modeFromQuery)
    }

    // MARK: - CLI: BrotherPaul --start [--mode "Name"]

    private func handleLaunchArguments() {
        let args = CommandLine.arguments
        guard args.contains("--start") else { return }

        let modeArg: String?
        if let idx = args.firstIndex(of: "--mode"), idx + 1 < args.count {
            modeArg = args[idx + 1]
        } else {
            modeArg = nil
        }
        launch(modeName: modeArg)
    }

    // MARK: - Shared launch entry point

    private func launch(modeName: String?) {
        let config = ConfigManager.shared.config
        let requested = modeName ?? config.defaultMode

        guard let mode = config.mode(named: requested) else {
            NSLog("BrotherPaul: unknown mode '%@'", requested)
            return
        }

        AppLauncher.launch(mode: mode, hideOthers: config.hideOthersAfterLaunch)

        if config.missionControl.openOnStartWork {
            // Launched apps activate themselves over ~1-3s and would bury an
            // immediately-shown Mission Control window. Open it after the storm
            // settles so it lands on top, then behaves as a normal window the
            // user can send behind by clicking another app.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                self.missionControl.show()
            }
        }
    }
}
