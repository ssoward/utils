import AppKit
import UserNotifications

enum AppLauncher {

    static func launch(mode: LaunchMode, hideOthers: Bool) {
        NSLog("BrotherPaul: launching mode '%@' with %d app(s)", mode.name, mode.apps.count)

        for appName in mode.apps {
            launchApp(named: appName)
        }

        for urlString in mode.urls {
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }

        if hideOthers {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                hideOtherApps()
            }
        }

        notify(mode: mode)
    }

    private static func launchApp(named name: String) {
        let workspace = NSWorkspace.shared

        if let url = workspace.urlForApplication(withBundleIdentifier: name) {
            open(url: url)
            return
        }

        let candidates = [
            "/Applications/\(name).app",
            "/Applications/\(name)/\(name).app",
            "/System/Applications/\(name).app",
            ("~/Applications/\(name).app" as NSString).expandingTildeInPath
        ]

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                open(url: URL(fileURLWithPath: path))
                return
            }
        }

        NSLog("BrotherPaul: could not locate app '%@'", name)
    }

    private static func open(url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error = error {
                NSLog("BrotherPaul: failed to open %@ — %@", url.path, error.localizedDescription)
            }
        }
    }

    private static func hideOtherApps() {
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            if app.bundleIdentifier == Bundle.main.bundleIdentifier { continue }
            if app.isActive { continue }
            app.hide()
        }
    }

    private static func notify(mode: LaunchMode) {
        // UNUserNotificationCenter requires a real .app bundle. When running via
        // `swift run` (bare executable, no bundle identifier) it throws an NSException,
        // so we log instead and only post a real banner once installed as BrotherPaul.app.
        guard Bundle.main.bundleIdentifier != nil else {
            NSLog("BrotherPaul: %@ session started (no bundle — skipping notification)", mode.name)
            return
        }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Brother Paul"
            content.body = "Good morning. \(mode.name) session started."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            center.add(request, withCompletionHandler: nil)
        }
    }
}
