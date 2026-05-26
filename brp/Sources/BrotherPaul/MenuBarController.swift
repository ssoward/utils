import AppKit
import SwiftUI

final class MenuBarController: NSObject, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    /// Called whenever the menu mutates `AppConfig` (toggles, etc.) so the
    /// rest of the app can re-apply behavior such as installing hotkeys.
    var onConfigChanged: (() -> Void)?

    /// Invoked when the user picks "Mission Control" from the menu.
    var onShowMissionControl: (() -> Void)?

    func install() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "brain.head.profile",
                accessibilityDescription: "Brother Paul"
            )
            button.toolTip = "Brother Paul — start my work"
        }
        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let config = ConfigManager.shared.config

        let header = NSMenuItem(title: "Brother Paul", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let startTitle = "Start \(config.defaultMode) Session"
        let startItem = NSMenuItem(
            title: startTitle,
            action: #selector(startDefault),
            keyEquivalent: "s"
        )
        startItem.target = self
        menu.addItem(startItem)

        let endTitle = "End \(config.defaultMode) Session"
        let endItem = NSMenuItem(
            title: endTitle,
            action: #selector(endDefault),
            keyEquivalent: ""
        )
        endItem.target = self
        menu.addItem(endItem)

        let mcItem = NSMenuItem(
            title: "Mission Control…",
            action: #selector(showMissionControl),
            keyEquivalent: "m"
        )
        mcItem.target = self
        menu.addItem(mcItem)

        let modesMenu = NSMenu(title: "Modes")
        for mode in config.modes {
            let item = NSMenuItem(
                title: mode.name,
                action: #selector(startNamedMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.name
            modesMenu.addItem(item)
        }
        let modesItem = NSMenuItem(title: "Modes", action: nil, keyEquivalent: "")
        menu.setSubmenu(modesMenu, for: modesItem)
        menu.addItem(modesItem)

        menu.addItem(.separator())

        let hideItem = NSMenuItem(
            title: "Hide Other Apps After Launch",
            action: #selector(toggleHideOthers),
            keyEquivalent: ""
        )
        hideItem.target = self
        hideItem.state = config.hideOthersAfterLaunch ? .on : .off
        menu.addItem(hideItem)

        menu.addItem(.separator())

        // Snap submenu
        let snapMenu = NSMenu(title: "Snap")
        let zonesInOrder: [(SnapZone, String)] = [
            (.leftHalf,            "⌃⌥ ←"),
            (.rightHalf,           "⌃⌥ →"),
            (.topHalf,             "⌃⌥ ↑"),
            (.bottomHalf,          "⌃⌥ ↓"),
            (.topLeftQuarter,      "⌃⌥ U"),
            (.topRightQuarter,     "⌃⌥ I"),
            (.bottomLeftQuarter,   "⌃⌥ J"),
            (.bottomRightQuarter,  "⌃⌥ K"),
            (.maximize,            "⌃⌥ ↩"),
            (.center,              "⌃⌥ C"),
        ]
        for (zone, shortcut) in zonesInOrder {
            let item = NSMenuItem(
                title: "\(zone.displayName)   \(shortcut)",
                action: #selector(snapToZone(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = zone.rawValue
            snapMenu.addItem(item)
        }
        snapMenu.addItem(.separator())

        let dragToggle = NSMenuItem(
            title: "Drag Window to Edge to Snap",
            action: #selector(toggleDragSnap),
            keyEquivalent: ""
        )
        dragToggle.target = self
        dragToggle.state = config.enableDragSnap ? .on : .off
        snapMenu.addItem(dragToggle)

        let snapEnabled = NSMenuItem(
            title: "Enable Window Snap",
            action: #selector(toggleSnap),
            keyEquivalent: ""
        )
        snapEnabled.target = self
        snapEnabled.state = config.enableSnap ? .on : .off
        snapMenu.addItem(snapEnabled)

        if !WindowSnapper.ensureAccessibility() {
            snapMenu.addItem(.separator())
            let grant = NSMenuItem(
                title: "Grant Accessibility Permission…",
                action: #selector(requestAccessibility),
                keyEquivalent: ""
            )
            grant.target = self
            snapMenu.addItem(grant)
        }

        let snapHeader = NSMenuItem(title: "Snap Focused Window", action: nil, keyEquivalent: "")
        menu.setSubmenu(snapMenu, for: snapHeader)
        menu.addItem(snapHeader)

        menu.addItem(.separator())

        let openConfig = NSMenuItem(
            title: "Open Config…",
            action: #selector(openConfigFile),
            keyEquivalent: ","
        )
        openConfig.target = self
        menu.addItem(openConfig)

        let editVerses = NSMenuItem(
            title: "Edit Daily Verses…",
            action: #selector(openVersesFile),
            keyEquivalent: ""
        )
        editVerses.target = self
        menu.addItem(editVerses)

        let reload = NSMenuItem(
            title: "Reload Config",
            action: #selector(reloadConfig),
            keyEquivalent: "r"
        )
        reload.target = self
        menu.addItem(reload)

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ""
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let about = NSMenuItem(
            title: "About Brother Paul",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    @objc private func startDefault() {
        let config = ConfigManager.shared.config
        let mode = config.mode(named: config.defaultMode) ?? config.modes.first
        guard let mode = mode else { return }
        AppLauncher.launch(mode: mode, hideOthers: config.hideOthersAfterLaunch)
    }

    @objc private func startNamedMode(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
              let mode = ConfigManager.shared.config.mode(named: name) else { return }
        AppLauncher.launch(
            mode: mode,
            hideOthers: ConfigManager.shared.config.hideOthersAfterLaunch
        )
    }

    @objc private func endDefault() {
        let config = ConfigManager.shared.config
        let mode = config.mode(named: config.defaultMode) ?? config.modes.first
        guard let mode = mode else { return }
        AppLauncher.end(mode: mode)
    }

    @objc private func toggleHideOthers() {
        var config = ConfigManager.shared.config
        config.hideOthersAfterLaunch.toggle()
        try? ConfigManager.shared.write(config)
        rebuildMenu()
        onConfigChanged?()
    }

    @objc private func snapToZone(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let zone = SnapZone(rawValue: raw) else { return }
        if !WindowSnapper.ensureAccessibility() {
            _ = WindowSnapper.ensureAccessibility(prompt: true)
            return
        }
        WindowSnapper.snap(to: zone)
    }

    @objc private func toggleSnap() {
        var config = ConfigManager.shared.config
        config.enableSnap.toggle()
        try? ConfigManager.shared.write(config)
        rebuildMenu()
        onConfigChanged?()
    }

    @objc private func toggleDragSnap() {
        var config = ConfigManager.shared.config
        config.enableDragSnap.toggle()
        try? ConfigManager.shared.write(config)
        rebuildMenu()
        onConfigChanged?()
    }

    @objc private func requestAccessibility() {
        _ = WindowSnapper.ensureAccessibility(prompt: true)
    }

    @objc private func showMissionControl() {
        onShowMissionControl?()
    }

    @objc private func openConfigFile() {
        NSWorkspace.shared.open(ConfigManager.shared.configFile)
    }

    @objc private func openVersesFile() {
        VerseOfTheDay.installSeed()
        NSWorkspace.shared.open(VerseOfTheDay.customFileURL)
    }

    @objc private func reloadConfig() {
        do {
            try ConfigManager.shared.reload()
            rebuildMenu()
            onConfigChanged?()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't reload config"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func showSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView { [weak self] in
            self?.rebuildMenu()
            self?.onConfigChanged?()
        }
        let hosting = NSHostingController(rootView: view)
        let window = KeyboardCloseWindow(contentViewController: hosting)
        window.title = "Brother Paul — Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 520, height: 480))
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
