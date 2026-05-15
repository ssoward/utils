# Brother Paul

> "Brother Paul, start my work."

A native macOS menu bar app that launches your entire work environment with one
click or one voice command, and snaps any window to halves / corners /
maximize with global hotkeys or drag-to-edge. Local, private, configurable
via JSON.

- New users start here: **[USER_GUIDE.md](USER_GUIDE.md)**
- Product spec: **[Brother-Paul-PRD.md](Brother-Paul-PRD.md)**
- The rest of this file is reference for developers and power users.

---

## Quick start

Requires macOS 13+ and a recent Swift toolchain (Xcode 15+ or the matching
command-line tools).

```bash
# Run directly (foreground, menu-bar icon appears)
swift run BrotherPaul

# Or build a real BrotherPaul.app bundle in ./build/
./build-app.sh
open build/BrotherPaul.app
```

The first run creates `~/Library/Application Support/BrotherPaul/config.json`
with the default apps and modes (Full / Deep Work / Meetings / Admin).

---

## Menu bar

Click the brain icon in the menu bar:

- **Start Full Work Session** — launch every app in the Full mode
- **Modes ▸** — pick Deep Work, Meetings, Admin, or any custom mode
- **Hide Other Apps After Launch** — toggle "hide others after launch"
- **Snap Focused Window ▸** — snap to half / quarter / maximize / center;
  toggle drag-to-edge and the master snap switch; quick link to grant
  Accessibility permission
- **Open Config…** — opens `config.json` in your default editor
- **Reload Config** — re-reads the file from disk
- **Settings…** — SwiftUI editor for modes and the default mode
- **About Brother Paul**
- **Quit**

---

## Configuration

Edit `~/Library/Application Support/BrotherPaul/config.json`. Example:

```json
{
  "hideOthersAfterLaunch": true,
  "enableSnap": true,
  "enableDragSnap": true,
  "defaultMode": "Full",
  "modes": [
    {
      "name": "Full",
      "apps": ["Microsoft Teams", "Microsoft Outlook", "Google Chrome", "Slack"],
      "urls": []
    },
    {
      "name": "Deep Work",
      "apps": ["Google Chrome", "Slack", "Notion"],
      "urls": []
    },
    {
      "name": "Meetings",
      "apps": ["Microsoft Teams", "Microsoft Outlook", "zoom.us"],
      "urls": []
    },
    {
      "name": "Admin",
      "apps": ["Microsoft Outlook", "Google Chrome"],
      "urls": ["https://mail.google.com"]
    }
  ]
}
```

| Key                      | Default | Effect                                          |
|--------------------------|---------|-------------------------------------------------|
| `hideOthersAfterLaunch`  | `true`  | Hide non-session apps ~1 s after launch         |
| `enableSnap`             | `true`  | Master switch for hotkeys + drag-snap           |
| `enableDragSnap`         | `true`  | Drop a window-drag at an edge to snap it        |
| `defaultMode`            | `"Full"`| Mode used by `brotherpaul://start` with no `?mode` |
| `modes[]`                | 4 modes | Each `{ name, apps[], urls[] }`                 |

Older `config.json` files (without `enableSnap` / `enableDragSnap`) decode
correctly — missing fields default to `true`, and the fields are written back
out the next time you change a setting from the menu or Settings window.

Each `apps` entry is a macOS application name (the same name as in
`/Applications`, without the `.app`). `urls` entries are opened in your
default browser after the apps launch.

After editing, choose **Reload Config** from the menu.

---

## Voice command (Siri Shortcut)

Brother Paul registers a `brotherpaul://` URL scheme so a Siri Shortcut can fire
a launch whether the app is already running or not.

URLs:
- `brotherpaul://start` — runs the default mode
- `brotherpaul://start?mode=Deep%20Work` — runs a named mode

Setup:
1. Build and install the app:
   ```bash
   ./build-app.sh
   cp -R build/BrotherPaul.app /Applications/
   open /Applications/BrotherPaul.app
   ```
2. Open **Shortcuts.app** → **+** to create a new shortcut.
3. Add the action **Open URLs** and set the URL to `brotherpaul://start`
   (or `brotherpaul://start?mode=Deep%20Work` for a specific mode).
4. Name the shortcut **"Brother Paul"**.
5. Enable **Use with Siri** so "Hey Siri, Brother Paul" works.

Now saying "Brother Paul" runs the default mode every time, even when the app
is already in the menu bar.

### CLI alternative

For testing from the terminal:

```bash
open "brotherpaul://start"
open "brotherpaul://start?mode=Meetings"

# Cold-launch form (only fires the launcher on first startup):
open -a BrotherPaul --args --start --mode "Deep Work"
```

---

## Window snap

Brother Paul includes Rectangle/Magnet-style window snapping for the focused
window of any app. Requires **Accessibility** permission (the menu has a
"Grant Accessibility Permission…" item that opens the right pane).

### Hotkeys (Ctrl+Opt)

| Shortcut       | Action               |
|----------------|----------------------|
| ⌃⌥ ←           | Left half            |
| ⌃⌥ →           | Right half           |
| ⌃⌥ ↑           | Top half             |
| ⌃⌥ ↓           | Bottom half          |
| ⌃⌥ U / I       | Top-left / Top-right ¼ |
| ⌃⌥ J / K       | Bottom-left / Bottom-right ¼ |
| ⌃⌥ ↩           | Maximize             |
| ⌃⌥ C           | Center               |

### Drag-to-edge

Drag a window's title bar to a screen edge or corner and release; the window
snaps to the matching zone. Triggers only when the window actually moved
during the drag (so accidental clicks at the screen edge don't snap).

Toggle this off any time via **Snap Focused Window ▸ Drag Window to Edge to Snap**
(or set `enableDragSnap: false` in `config.json`).

## Permissions

The first launch may prompt for:

- **Accessibility** — required for window snapping and "Hide Other Apps".
  Open **System Settings → Privacy & Security → Accessibility** and enable
  Brother Paul.
- **Notifications** — for the "Good morning, work session started" banner.

You can grant or revoke these under **System Settings → Privacy & Security**.

---

## Project layout

```
brpaul/
├── Brother-Paul-PRD.md         # Product requirements
├── README.md                   # This file (developer / reference)
├── USER_GUIDE.md               # End-user walkthrough
├── Package.swift               # Swift Package manifest
├── Sources/BrotherPaul/
│   ├── main.swift              # Entry point — starts the AppKit run loop
│   ├── AppDelegate.swift       # Lifecycle, URL handler, snap bootstrap
│   ├── MenuBarController.swift # NSStatusItem + menu + Settings window
│   ├── SettingsView.swift      # SwiftUI editor for modes
│   ├── Models.swift            # AppConfig + LaunchMode (Codable)
│   ├── ConfigManager.swift     # Reads/writes ~/Library/.../config.json
│   ├── AppLauncher.swift       # Launches apps, opens URLs, hides others
│   ├── SnapZone.swift          # Snap zones + cursor-to-zone mapping
│   ├── WindowSnapper.swift     # AXUIElement move/resize of focused window
│   ├── HotkeyManager.swift     # Carbon RegisterEventHotKey (Ctrl+Opt+*)
│   └── DragSnapper.swift       # Global mouse monitor → drag-to-edge snap
├── Resources/
│   ├── Info.plist              # Bundle metadata (LSUIElement + URL scheme)
│   └── config.example.json     # Seed config copied on first run
└── build-app.sh                # Wraps the binary into BrotherPaul.app
```

---

## Troubleshooting

**Hotkeys don't do anything.**
1. Brain icon → **Snap Focused Window ▸ Enable Window Snap** is on.
2. Brain icon → **Snap Focused Window ▸ Grant Accessibility Permission…** —
   make sure `/Applications/BrotherPaul.app` is in the list and toggled on.
3. If you ever rebuild and reinstall, macOS may remember the old binary's
   permission grant. Toggle Brother Paul off and on once in
   **System Settings → Privacy & Security → Accessibility**.

**Hotkey conflicts with another app.**
`⌃⌥ ←` overlaps with some terminal "previous-word" bindings. If you need a
different modifier, edit `Sources/BrotherPaul/HotkeyManager.swift` — the
`modifiers` property is a single line — and rebuild. A config-driven
remap is a future enhancement.

**Drag-to-edge snaps when I didn't intend it.**
The detector only fires when the focused window actually moved during the
drag, but if you find it noisy, toggle **Drag Window to Edge to Snap** off
under the Snap submenu.

**`brotherpaul://start` doesn't launch anything.**
Confirm `/Applications/BrotherPaul.app` owns the scheme:
```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -dump | grep -B1 -A2 'claimed schemes:[[:space:]]*brotherpaul:'
```
If a stale `build/BrotherPaul.app` is listed, unregister it:
```bash
.../lsregister -u /path/to/old/BrotherPaul.app
.../lsregister -f /Applications/BrotherPaul.app
```

**One of the apps in a mode doesn't open.**
Check that the name in `apps[]` matches the bundle name in `/Applications/`
(e.g. `Microsoft Teams`, not `Teams`). You can also use a bundle identifier
(`com.microsoft.teams2`) — `AppLauncher.launchApp(named:)` tries that first.

---

## Uninstall

```bash
osascript -e 'tell application "BrotherPaul" to quit'
rm -rf /Applications/BrotherPaul.app
rm -rf "$HOME/Library/Application Support/BrotherPaul"
```
Then remove BrotherPaul from **System Settings → Privacy & Security → Accessibility**
(and Notifications, if listed) and delete any Siri Shortcut you created.

---

## License

[MIT](LICENSE) © 2026 Scott Soward
