import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    private lazy var menuBar = MenuBarController()
    private let hotkeys = HotkeyManager()
    private let dragSnapper = DragSnapper()
    private lazy var missionControl = MissionControlWindow()

    // main.swift constructs us from top-level (nonisolated) code.
    nonisolated override init() { super.init() }

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
        MorningReminders.installSeed()
        menuBar.install()
        menuBar.onConfigChanged = { [weak self] in self?.applySnapConfig() }
        menuBar.onShowMissionControl = { [weak self] in
            Task { @MainActor in self?.missionControl.show() }
        }
        menuBar.onStartMode = { [weak self] name in self?.launch(modeName: name) }
        menuBar.onEndMode = { [weak self] name in self?.endSession(modeName: name) }

        // Todos: background monitor drives the menu-bar badge + overdue nudges.
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
        TodoMonitor.shared.onChange = { [weak self] snap in self?.menuBar.updateBadge(snap) }
        TodoMonitor.shared.start()

        applySnapConfig()

        handleLaunchArguments()
    }

    @MainActor
    func showMissionControl() {
        missionControl.show()
    }

    // MARK: - Notifications

    /// Show our banners even while a Brother Paul window is frontmost.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    /// Clicking an overdue-todo nudge opens Mission Control.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let isNudge = response.notification.request.identifier == TodoMonitor.nudgeIdentifier
        Task { @MainActor in
            if isNudge { self.missionControl.show() }
            completionHandler()
        }
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

    // MARK: - URL scheme: brotherpaul://start?mode=Deep%20Work or brotherpaul://stop

    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else {
            return
        }
        handle(urlString: urlString)
    }

    /// Parses a brotherpaul:// URL and dispatches to launch/end. Separated from
    /// the Apple Event plumbing so it can be driven directly by tests.
    func handle(urlString: String) {
        guard let action = URLActionParser.parse(urlString) else { return }

        switch action {
        case .start(let mode):
            launch(modeName: mode)
        case .stop(let mode):
            endSession(modeName: mode)
        case .unknown(let name):
            NSLog("BrotherPaul: ignoring URL with unknown action '%@'", name)
        }
    }

    // MARK: - CLI: BrotherPaul --start [--mode "Name"] or --stop [--mode "Name"]

    private func handleLaunchArguments() {
        let args = CommandLine.arguments
        let modeArg: String? = {
            if let idx = args.firstIndex(of: "--mode"), idx + 1 < args.count {
                return args[idx + 1]
            }
            return nil
        }()

        if args.contains("--start") {
            launch(modeName: modeArg)
        } else if args.contains("--stop") {
            endSession(modeName: modeArg)
        }
    }

    // MARK: - Shared launch entry point

    func launch(modeName: String?) {
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

    // MARK: - Shared end-session entry point

    func endSession(modeName: String?) {
        let config = ConfigManager.shared.config
        let requested = modeName ?? config.defaultMode

        guard let mode = config.mode(named: requested) else {
            NSLog("BrotherPaul: unknown mode '%@'", requested)
            return
        }

        AppLauncher.end(mode: mode)
    }
}
