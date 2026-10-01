import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    /// Called whenever the menu mutates `AppConfig` (toggles, etc.) so the
    /// rest of the app can re-apply behavior such as installing hotkeys.
    var onConfigChanged: (() -> Void)?

    /// Invoked when the user picks "Mission Control" from the menu.
    var onShowMissionControl: (() -> Void)?

    /// Start / end a session by mode name (nil = default mode). Routed through
    /// AppDelegate so the menu behaves exactly like the URL scheme and CLI
    /// (e.g. honoring `openOnStartWork`).
    var onStartMode: ((String?) -> Void)?
    var onEndMode: ((String?) -> Void)?

    /// Max todos listed inline in the menu before "Show all…".
    private let menuTodoLimit = 8

    func install() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "brain.head.profile",
                accessibilityDescription: "Brother Paul"
            )
            button.toolTip = "Brother Paul — start my work"
            button.imagePosition = .imageLeading
        }
        rebuildMenu()
        updateBadge(TodoMonitor.shared.snapshot)
    }

    /// Menu-bar badge: count of overdue + due-today todos. The icon turns red
    /// while anything is overdue and orange when something is due today, so a
    /// glance at the menu bar is enough to know a todo needs you.
    func updateBadge(_ snapshot: TodoSnapshot) {
        guard let button = statusItem?.button else { return }
        let cfg = ConfigManager.shared.config.missionControl
        let badge = TodoBadge(snapshot: snapshot, enabled: cfg.showTodoCountInMenuBar && cfg.includeReminders)

        button.contentTintColor = {
            switch badge.level {
            case .overdue: return .systemRed
            case .dueToday: return .systemOrange
            case .none: return nil
            }
        }()
        if badge.text.isEmpty {
            button.attributedTitle = NSAttributedString(string: "")
        } else {
            button.attributedTitle = NSAttributedString(string: badge.text, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
                .foregroundColor: badge.level == .overdue ? NSColor.systemRed : NSColor.labelColor,
            ])
        }
        button.toolTip = badge.toolTip
    }

    func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let config = ConfigManager.shared.config

        let header = NSMenuItem(title: "Brother Paul", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if config.missionControl.includeReminders {
            addTodoItems(to: menu)
            menu.addItem(.separator())
        }

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

        let editReminders = NSMenuItem(
            title: "Edit Morning Reminders…",
            action: #selector(openRemindersFile),
            keyEquivalent: ""
        )
        editReminders.target = self
        menu.addItem(editReminders)

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
        // Menu shows the cached snapshot instantly; pull a fresh one for next time.
        TodoMonitor.shared.refresh()
    }

    // MARK: - Todos in the menu

    private func addTodoItems(to menu: NSMenu) {
        let monitor = TodoMonitor.shared
        let snap = monitor.snapshot

        let headerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        headerItem.attributedTitle = TodoBadge.menuHeader(for: snap, loaded: monitor.hasLoaded)
        menu.addItem(headerItem)

        for item in snap.items.prefix(menuTodoLimit) {
            menu.addItem(todoMenuItem(item))
        }

        if snap.items.count > menuTodoLimit {
            let more = NSMenuItem(
                title: "Show all \(snap.items.count) todos…",
                action: #selector(showMissionControl),
                keyEquivalent: ""
            )
            more.target = self
            menu.addItem(more)
        }

        let todoItem = NSMenuItem(
            title: "New Todo…",
            action: #selector(newTodo),
            keyEquivalent: "t"
        )
        todoItem.target = self
        menu.addItem(todoItem)
    }

    private func todoMenuItem(_ item: DigestItem) -> NSMenuItem {
        let mi = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
        let title = item.title.count > 48 ? String(item.title.prefix(47)) + "…" : item.title
        let attributed = NSMutableAttributedString(string: title, attributes: [
            .font: NSFont.menuFont(ofSize: 0),
        ])
        if let sub = item.subtitle, !sub.isEmpty {
            attributed.append(NSAttributedString(string: "   \(sub)", attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: item.priority >= 100 ? NSColor.systemRed : NSColor.secondaryLabelColor,
            ]))
        }
        mi.attributedTitle = attributed
        mi.image = TodoBadge.dotImage(priority: item.priority)

        let sub = NSMenu()
        let id = item.externalID ?? ""

        let done = NSMenuItem(title: "Complete", action: #selector(completeTodo(_:)), keyEquivalent: "")
        done.target = self
        done.representedObject = id
        done.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: nil)
        sub.addItem(done)
        sub.addItem(.separator())

        for option in RemindersFetcher.SnoozeOption.allCases {
            guard let target = option.target() else { continue }
            let s = NSMenuItem(title: option.title, action: #selector(snoozeTodo(_:)), keyEquivalent: "")
            s.target = self
            s.representedObject = SnoozeRequest(identifier: id, until: target)
            sub.addItem(s)
        }
        sub.addItem(.separator())

        let open = NSMenuItem(title: "Open Reminders", action: #selector(openReminders), keyEquivalent: "")
        open.target = self
        sub.addItem(open)

        mi.submenu = sub
        return mi
    }

    @objc private func completeTodo(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, !id.isEmpty else { return }
        Task { await TodoMonitor.shared.complete(identifier: id) }
    }

    @objc private func snoozeTodo(_ sender: NSMenuItem) {
        guard let req = sender.representedObject as? SnoozeRequest, !req.identifier.isEmpty else { return }
        Task { await TodoMonitor.shared.snooze(identifier: req.identifier, until: req.until) }
    }

    @objc private func openReminders() {
        RemindersFetcher.openRemindersApp()
    }

    // MARK: - Sessions

    @objc private func startDefault() {
        onStartMode?(nil)
    }

    @objc private func startNamedMode(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        onStartMode?(name)
    }

    @objc private func endDefault() {
        onEndMode?(nil)
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

    /// Fast todo capture from the menu bar. A date/time in the text ("…tomorrow
    /// 3pm") becomes the due time and fires a reminder notification.
    @objc private func newTodo() {
        let alert = NSAlert()
        alert.messageText = "New Todo"
        alert.informativeText = "Add a reminder to your default Reminders list. Include a time like \u{201C}tomorrow 3pm\u{201D} to get notified."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "e.g. Email the quarterly report"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let parsed = TodoParser.parse(field.stringValue)
        guard !parsed.title.isEmpty else { return }
        Task { await TodoMonitor.shared.add(title: parsed.title, dueDate: parsed.dueDate) }
    }

    @objc private func openConfigFile() {
        NSWorkspace.shared.open(ConfigManager.shared.configFile)
    }

    @objc private func openVersesFile() {
        VerseOfTheDay.installSeed()
        NSWorkspace.shared.open(VerseOfTheDay.customFileURL)
    }

    @objc private func openRemindersFile() {
        MorningReminders.installSeed()
        NSWorkspace.shared.open(MorningReminders.customFileURL)
    }

    @objc private func reloadConfig() {
        do {
            try ConfigManager.shared.reload()
            rebuildMenu()
            onConfigChanged?()
            TodoMonitor.shared.refresh()
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
            self?.settingsWindow?.close()
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

/// Carries a snooze target through NSMenuItem.representedObject.
private final class SnoozeRequest: NSObject {
    let identifier: String
    let until: Date
    init(identifier: String, until: Date) {
        self.identifier = identifier
        self.until = until
    }
}
