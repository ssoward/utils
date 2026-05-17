# Brother Paul

> "Brother Paul, start my work."

A native macOS menu bar app that:

- **Launches your work apps** with one click, URL, or voice command.
- **Snaps any window** to halves / corners / maximize via global hotkeys
  or drag-to-edge.
- Shows a **Mission Control digest** of upcoming events (EventKit +
  Microsoft Graph), priority email (Outlook AppleScript + Gmail API),
  recent notifications (NotificationCenter DB), and a **daily Christ-focused
  verse** rotated from a 132-passage library of the Book of Mormon and
  the KJV Gospels.

Local, private, configurable via JSON.

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

- **Start Full Work Session** (`⌘S`) — launch every app in the Full mode
- **End Full Session** — gracefully quit every app in the Full mode (apps
  with unsaved work get their normal save prompt; Brother Paul stays
  running)
- **Mission Control…** (`⌘M`) — open the daily digest window
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
  "modes": [ /* ... */ ],
  "missionControl": {
    "includeCalendar": true,
    "includeOutlook": true,
    "includeGmail": false,
    "includeNotifications": true,
    "lookbackHours": 24,
    "vipSenders": ["boss@example.com", "Project Alpha"],
    "notificationAppBlocklist": ["com.apple.systemnotifications"],
    "openOnStartWork": true,
    "gmail": {
      "clientID": "",
      "clientSecret": "",
      "refreshToken": ""
    }
  }
}
```

See `Resources/config.example.json` for the full default file (including all
four modes).

| Key                      | Default | Effect                                          |
|--------------------------|---------|-------------------------------------------------|
| `hideOthersAfterLaunch`  | `true`  | Hide non-session apps ~1 s after launch         |
| `enableSnap`             | `true`  | Master switch for hotkeys + drag-snap           |
| `enableDragSnap`         | `true`  | Drop a window-drag at an edge to snap it        |
| `defaultMode`            | `"Full"`| Mode used by `brotherpaul://start` with no `?mode` |
| `modes[]`                | 4 modes | Each `{ name, apps[], urls[] }`                 |
| `missionControl.*`       | see [Mission Control](#mission-control) | Daily digest config |

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
- `brotherpaul://stop` — gracefully quits every app in the default mode
- `brotherpaul://stop?mode=Meetings` — quits a named mode's apps

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
open "brotherpaul://stop"
open "brotherpaul://stop?mode=Meetings"

# Cold-launch form (only fires the launcher on first startup):
open -a BrotherPaul --args --start --mode "Deep Work"
open -a BrotherPaul --args --stop  --mode "Deep Work"
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

## Mission Control

A daily digest window that surfaces:

- **Upcoming events** — next *N* hours from your macOS Calendar (any account
  added to Internet Accounts).
- **Priority email** — unread Outlook mail (AppleScript bridge) and unread
  Gmail (Gmail REST API), with VIP-sender boost.
- **Recent notifications** — last *N* hours of macOS Notification Center,
  read directly from its SQLite database (requires Full Disk Access).

Open it via:

- Menu bar → **Mission Control…** (`⌘M`)
- Automatically when you fire `brotherpaul://start` — controlled by
  `missionControl.openOnStartWork`

### Config

| Key                                        | Default | Effect                                              |
|--------------------------------------------|---------|-----------------------------------------------------|
| `includeCalendar`                          | `true`  | Fetch events from EventKit (macOS Calendar.app)     |
| `includeOutlook`                           | `true`  | Run Outlook AppleScript for unread mail             |
| `includeOutlookCalendar`                   | `true`  | Outlook AppleScript for events — broken in 2024+ Outlook (Microsoft removed the `calendar event` class). Disable and use Graph instead, or subscribe to an Outlook iCal feed in Calendar.app. |
| `includeGraphCalendar`                     | `false` | Call Microsoft Graph for Outlook events (recommended Outlook path) |
| `includeGmail`                             | `false` | Call Gmail API (needs OAuth setup)                  |
| `includeNotifications`                     | `true`  | Read NotificationCenter DB (needs Full Disk Access) |
| `includeVerseOfDay`                        | `true`  | Show the daily verse card at the top of the digest  |
| `lookbackHours`                            | `24`    | Window for email + notifications, lookahead for events |
| `vipSenders[]`                             | `[]`    | Substrings matched against from / display name      |
| `notificationAppBlocklist[]`               | `[]`    | Bundle IDs to drop from the notifications section   |
| `openOnStartWork`                          | `true`  | Auto-open after a successful session launch         |
| `gmail.clientID/clientSecret/refreshToken` | `""`    | Filled in by `bin/brpaul-gmail-auth.sh`             |
| `graph.clientID/tenant/refreshToken`       | `""`    | Filled in by `bin/brpaul-graph-auth.sh`             |

### Gmail OAuth setup (one-time)

1. Google Cloud Console → create project (or reuse one).
2. **APIs & Services → Library** → enable **Gmail API**.
3. **APIs & Services → OAuth consent screen** → External, Testing, add
   yourself as a test user.
4. **APIs & Services → Credentials** → Create credentials → OAuth client ID,
   Application type **Desktop app**. Note the client ID + secret.
5. From the repo root:
   ```bash
   ./bin/brpaul-gmail-auth.sh <CLIENT_ID> <CLIENT_SECRET>
   ```
   Your browser opens, you consent, the script captures the refresh token
   and prints a JSON snippet ready to paste into
   `~/Library/Application Support/BrotherPaul/config.json` under
   `missionControl.gmail`. Then choose **Reload Config** from the menu.

### Permissions

The first time each section runs you'll see a prompt:

- **Calendar** — System Settings → Privacy & Security → **Calendars**.
- **Automation** (for Outlook) — granted on the first AppleScript call;
  configured under **Automation** in Privacy & Security.
- **Full Disk Access** (for notification history) — drop
  `/Applications/BrotherPaul.app` into the **Full Disk Access** list. macOS
  doesn't prompt for this one — you have to add it manually.

If any source can't run, Mission Control shows a one-line status under that
section explaining what's missing.

### Verse of the Day

A Christ-focused verse renders at the top of the digest, rotated daily.
The library ships with **132 public-domain passages** — 61 from the Book of
Mormon and 71 from the four Gospels of the KJV New Testament. Selection is
`day-of-year mod count`, so the same calendar date shows the same verse year
over year.

The user-editable file lives at
`~/Library/Application Support/BrotherPaul/verses.json`. Open it from the
menu via **Edit Daily Verses…** — add, remove, or correct entries. Each
entry has `reference`, `text`, and an optional `source` ("Book of Mormon",
"KJV New Testament", or anything you like — it's printed as the citation
suffix).

A seed-version file (`.verses-seed-version`) lets new releases push expanded
defaults onto existing installs. Increment that marker to a high number if
you've hand-edited the file and want to lock your edits in.

Disable the card entirely: `missionControl.includeVerseOfDay: false`.

### Outlook calendar without Azure: iCal subscribe

If your org blocks both Microsoft Graph app registration **and** legacy
Outlook AppleScript (which Microsoft has been deprecating), you can still
get Outlook events into Mission Control through EventKit:

1. In Outlook (or [outlook.office.com](https://outlook.office.com) →
   **Settings ⚙️ → Calendar → Shared calendars → Publish a calendar**),
   publish your calendar and copy the **`.ics`** URL.
2. **Calendar.app → File → New Calendar Subscription** → paste the URL →
   set auto-refresh.
3. Ensure the new subscription's checkbox is **on** in Calendar.app's
   sidebar (EventKit only returns events from visible calendars).
4. **Mission Control → Refresh**.

---

## Permissions

The first launch may prompt for:

- **Accessibility** — required for window snapping and "Hide Other Apps".
  Open **System Settings → Privacy & Security → Accessibility** and enable
  Brother Paul.
- **Calendars** — Mission Control's Events section.
- **Automation** (Microsoft Outlook) — Mission Control's Email section.
- **Full Disk Access** — Mission Control's Notifications section (manual
  add; macOS doesn't prompt).
- **Notifications** — for the "Good morning, work session started" banner.

You can grant or revoke these under **System Settings → Privacy & Security**.

---

## Project layout

```
brpaul/
├── Brother-Paul-PRD.md         # Product requirements
├── README.md                   # This file (developer / reference)
├── USER_GUIDE.md               # End-user walkthrough
├── LICENSE                     # MIT
├── Package.swift               # Swift Package manifest
├── Sources/BrotherPaul/
│   ├── main.swift              # Entry point — starts the AppKit run loop
│   ├── AppDelegate.swift       # Lifecycle, URL handler, snap + MC bootstrap
│   ├── MenuBarController.swift # NSStatusItem + menu + Settings window
│   ├── SettingsView.swift      # SwiftUI editor for modes
│   ├── Models.swift            # AppConfig + LaunchMode + MissionControlConfig
│   ├── ConfigManager.swift     # Reads/writes ~/Library/.../config.json
│   ├── AppLauncher.swift       # Launches apps, opens URLs, hides others
│   ├── SnapZone.swift          # Snap zones + cursor-to-zone mapping
│   ├── WindowSnapper.swift     # AXUIElement move/resize of focused window
│   ├── HotkeyManager.swift     # Carbon RegisterEventHotKey (Ctrl+Opt+*)
│   ├── DragSnapper.swift       # Global mouse monitor → drag-to-edge snap
│   ├── MissionControlModels.swift      # Digest, DigestItem, SectionResult
│   ├── MissionControlCoordinator.swift # Async fan-out to fetchers
│   ├── MissionControlWindow.swift      # NSWindow wrapper
│   ├── MissionControlView.swift        # SwiftUI digest UI (collapsible)
│   ├── CalendarFetcher.swift           # EventKit upcoming events
│   ├── OutlookFetcher.swift            # AppleScript → Outlook unread mail
│   ├── OutlookCalendarFetcher.swift    # AppleScript → Outlook events (legacy)
│   ├── GmailFetcher.swift              # Gmail REST + OAuth refresh
│   ├── GraphCalendarFetcher.swift      # Microsoft Graph /me/calendarview
│   ├── NotificationsFetcher.swift      # SQLite → NotificationCenter db
│   └── VerseOfTheDay.swift             # 132-verse rotation, file-overridable
├── Resources/
│   ├── Info.plist              # Bundle metadata + usage descriptions
│   └── config.example.json     # Seed config copied on first run
├── bin/
│   ├── brpaul-gmail-auth.sh    # One-time Google OAuth dance
│   └── brpaul-graph-auth.sh    # One-time Microsoft Graph PKCE dance
├── ~/Library/Application Support/BrotherPaul/
│   ├── config.json                  # User-editable settings (auto-seeded)
│   ├── verses.json                  # User-editable verse library (auto-seeded)
│   └── .verses-seed-version         # Seed-version marker
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

**Mission Control: Outlook calendar shows "errno -1751" or "AppleScript failed".**
Microsoft has removed the `calendar event` AppleScript class from current
Outlook for Mac builds — there's no toggle that brings it back. Two reliable
workarounds: (1) Microsoft Graph integration (see USER_GUIDE.md → Outlook
calendar via Microsoft Graph), or (2) publish your Outlook calendar as `.ics`
and subscribe to it in macOS Calendar.app (see "Outlook calendar without
Azure" above).

**Mission Control: Outlook mail "AppleScript failed".**
Outlook mail AppleScript still works on most builds. If it fails with
`-1743`, you haven't granted Automation permission yet — System Settings →
Privacy & Security → Automation → BrotherPaul → toggle Microsoft Outlook on.

**Mission Control: "Couldn't read the notification database…".**
Drop `/Applications/BrotherPaul.app` into
**System Settings → Privacy & Security → Full Disk Access**, then click
Refresh. macOS doesn't prompt for this — you have to add it manually.

**Mission Control: "Gmail token refresh failed".**
Most common cause: you regenerated the OAuth client or revoked the grant in
[Google Account → Security → Third-party access](https://myaccount.google.com/permissions).
Run `./bin/brpaul-gmail-auth.sh` again and replace `refreshToken`.

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
