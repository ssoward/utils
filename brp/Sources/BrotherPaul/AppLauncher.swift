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

        notify(mode: mode, verb: "started")
    }

    /// Inverse of `launch`: for each app listed in the mode, find any matching
    /// running NSRunningApplication and send it a graceful Quit. Apps with
    /// unsaved work get their normal save prompt. Brother Paul never quits
    /// itself.
    static func end(mode: LaunchMode) {
        NSLog("BrotherPaul: ending mode '%@' (%d configured app(s))", mode.name, mode.apps.count)

        let myBundle = Bundle.main.bundleIdentifier
        let running = NSWorkspace.shared.runningApplications

        for appName in mode.apps {
            let matches = running.filter { app in
                if app.bundleIdentifier == myBundle { return false }
                if let bid = app.bundleIdentifier,
                   bid.caseInsensitiveCompare(appName) == .orderedSame { return true }
                if let name = app.localizedName,
                   name.caseInsensitiveCompare(appName) == .orderedSame { return true }
                return false
            }
            if matches.isEmpty {
                NSLog("BrotherPaul: '%@' not running, nothing to quit", appName)
                continue
            }
            for app in matches {
                NSLog("BrotherPaul: quitting %@", app.localizedName ?? appName)
                _ = app.terminate()
            }
        }

        notify(mode: mode, verb: "ended")
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

    private static func notify(mode: LaunchMode, verb: String) {
        // UNUserNotificationCenter requires a real .app bundle. When running via
        // `swift run` (bare executable, no bundle identifier) it throws an NSException,
        // so we log instead and only post a real banner once installed as BrotherPaul.app.
        guard Bundle.main.bundleIdentifier != nil else {
            NSLog("BrotherPaul: %@ session %@ (no bundle — skipping notification)", mode.name, verb)
            return
        }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Brother Paul"
            let prefix = verb == "started" ? "Good morning. " : ""
            content.body = "\(prefix)\(mode.name) session \(verb)."
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
