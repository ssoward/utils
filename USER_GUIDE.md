# Brother Paul — User Guide

> "Brother Paul, start my work."

A tiny macOS menu bar app that does two things very well:

1. **Launches your work apps** with one click, one URL, or one voice command.
2. **Snaps any window** to halves, corners, or fullscreen — with keyboard
   shortcuts or by dragging to a screen edge.

Everything is local. No accounts, no cloud, no analytics.

---

## 1. First-time setup (≈ 2 minutes)

### Install

```bash
./build-app.sh
cp -R build/BrotherPaul.app /Applications/
open /Applications/BrotherPaul.app
```

You should see a 🧠 brain icon appear in the right side of your menu bar.

### Grant Accessibility permission

Window snap and "Hide Other Apps" need this.

1. Click the 🧠 → **Snap Focused Window ▸ Grant Accessibility Permission…**
   (or open **System Settings → Privacy & Security → Accessibility** yourself).
2. Click **+** in the app list, choose `/Applications/BrotherPaul.app`.
3. Flip the switch **on**.

No restart needed. Brother Paul rechecks the permission whenever you open the
menu.

### Allow notifications (optional)

The first time you start a work session, macOS will ask if Brother Paul can
send notifications. Allow it and you'll see a "Good morning, Full session
started" banner. Deny it and everything still works — just no banner.

---

## 2. Start your work session

You have four ways. Pick whichever fits the moment.

### Click

🧠 → **Start Full Session** (or pick a different mode from **Modes ▸**).

### Voice

Set up a Siri Shortcut once:

1. Open **Shortcuts.app** → **+**.
2. Add the **Open URLs** action.
3. URL: `brotherpaul://start`.
4. Rename the shortcut to whatever you want Siri to recognize, e.g.
   **Start Work** or **Brother Paul**.
5. Make sure **System Settings → Apple Intelligence & Siri → Listen for "Siri"
   or "Hey Siri"** is on.

Now: "Hey Siri, Start Work."

To trigger a specific mode by voice, make a second shortcut named
**Deep Work** with URL `brotherpaul://start?mode=Deep%20Work`.

### Hotkey

Assign one in Shortcuts.app → your shortcut → **▸** menu → **Add Keyboard
Shortcut**. Brother Paul itself doesn't currently own a launch hotkey
(snap hotkeys live in `⌃⌥`, see below).

### Terminal

```bash
open brotherpaul://start
open "brotherpaul://start?mode=Meetings"
```

Handy for `cron` jobs, scripts, or one-off testing.

---

## 3. Snap any window

Once Accessibility is granted, snap works for **any app's focused window**.

### With the keyboard

| Shortcut       | Snaps to               |
|----------------|------------------------|
| **⌃⌥ ←**       | Left half              |
| **⌃⌥ →**       | Right half             |
| **⌃⌥ ↑**       | Top half               |
| **⌃⌥ ↓**       | Bottom half            |
| **⌃⌥ U**       | Top-left quarter       |
| **⌃⌥ I**       | Top-right quarter      |
| **⌃⌥ J**       | Bottom-left quarter    |
| **⌃⌥ K**       | Bottom-right quarter   |
| **⌃⌥ ↩**       | Maximize (visible frame, not Spaces-style fullscreen) |
| **⌃⌥ C**       | Center (60% × 70%)     |

### With the mouse

Drag a window's title bar to a screen edge or corner and release.

```
   top-left  ─┐   top  ─┐   ┌── top-right
    quarter   │ (maximize) │   quarter
              ▼            ▼
        ┌──────────────────────┐
   left │                      │ right
   half │                      │  half
        │                      │
        └──────────────────────┘
              ▲            ▲
              │            │
   bottom-left┘  bottom    └─ bottom-right
    quarter      half          quarter
```

Drop within ~6 px of the literal edge for halves/maximize, or in the 30 × 30
corner box for quarters. The snap only fires if the window actually *moved*
during the drag, so accidental clicks at the edge don't snap anything.

### Snap from the menu

🧠 → **Snap Focused Window ▸** then pick any zone. Useful when both hands are
already on the mouse.

### Turning snap off

- **Drag-snap noisy?** 🧠 → **Snap Focused Window ▸ Drag Window to Edge to Snap**
  to toggle just the drag feature.
- **Want all snap off?** 🧠 → **Snap Focused Window ▸ Enable Window Snap**.

Both are also persisted in `config.json` as `enableSnap` and `enableDragSnap`.

---

## 4. Customize your work sessions

Your sessions live in:

```
~/Library/Application Support/BrotherPaul/config.json
```

Two ways to edit it:

**Settings window** — 🧠 → **Settings…** — add/remove modes, add/remove apps,
pick the default mode, toggle "Hide Others After Launch". Click **Save**.

**Raw JSON** — 🧠 → **Open Config…** opens the file in your editor. After
saving, choose **Reload Config**.

### Example: add a "Writing" mode

```json
{
  "name": "Writing",
  "apps": ["Bear", "Safari"],
  "urls": ["https://www.google.com/search?q=word+of+the+day"]
}
```

Apps are matched by:

1. **Bundle identifier first** (e.g. `com.apple.Safari`) — most reliable.
2. **App name in `/Applications/`** (e.g. `Safari`).
3. **App name in `~/Applications/`** or `/System/Applications/` for system apps.

URLs are opened in your default browser after the apps launch.

### Make it your default

Set `"defaultMode": "Writing"` and now `brotherpaul://start` (and "Hey Siri,
Start Work") launches the Writing session.

---

## 5. Power-user tips

- **One Shortcut per mode.** Make Siri Shortcuts named "Deep Work",
  "Meetings", "Admin", each pointing at `brotherpaul://start?mode=…`.
  Now you can say any of them.
- **Combine with macOS Focus.** In **System Settings → Focus**, set a
  "Work" focus to auto-enable when you run the Shortcut.
- **Chain things.** Inside a Shortcut, follow **Open URLs** with **Open App**
  (Music / Spotify), **Set Brightness**, **Set Volume**, etc. Brother Paul
  takes care of the apps; macOS takes care of the rest.
- **Use snap with multi-monitor.** Snap zones are computed for the screen
  containing your cursor — drag a window across, hit `⌃⌥ →` and it snaps
  to the right half *of that screen*.
- **Keep the brain tidy.** If you toggle `hideOthersAfterLaunch` off, only
  the apps from the mode are activated — nothing else is touched.

---

## 6. Troubleshooting

**Nothing happens when I press `⌃⌥ ←`.**
Open **System Settings → Privacy & Security → Accessibility** and verify
Brother Paul is in the list AND the switch is on. After a reinstall, macOS
sometimes leaves the entry but flips the switch off.

**`⌃⌥ ←` does the wrong thing inside one app.**
That app has registered a global shortcut that overlaps. Either change the
shortcut in that app, or (last resort) edit `Sources/BrotherPaul/HotkeyManager.swift`
to use a different modifier (e.g. `controlKey | optionKey | shiftKey`) and
rebuild.

**Drag-to-edge keeps snapping when I didn't want it to.**
Toggle **Drag Window to Edge to Snap** off (🧠 → **Snap Focused Window ▸**).
You'll still have all the hotkeys.

**Apps in my session don't all launch.**
Open `config.json` and confirm each `apps[]` entry matches the name shown in
`/Applications/` (without `.app`). For weird names like `zoom.us`, copy the
name exactly as it appears in Finder.

**"Hey Siri, Start Work" doesn't trigger.**
- The shortcut name **is** the trigger phrase — name it exactly what you want
  to say.
- In **System Settings → Apple Intelligence & Siri**, "Listen for" must be on.
- The shortcut must be in your **Shortcuts library**, not in a folder Siri
  doesn't search.

**`brotherpaul://start` opens the wrong app or nothing.**
A previous build of Brother Paul might still be registered. Quit
Brother Paul and run:
```bash
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREG" -u path/to/old/BrotherPaul.app
"$LSREG" -f /Applications/BrotherPaul.app
open /Applications/BrotherPaul.app
```

**I want it to quit / I'm uninstalling.**
🧠 → **Quit**. To fully remove:
```bash
rm -rf /Applications/BrotherPaul.app
rm -rf "$HOME/Library/Application Support/BrotherPaul"
```
Then remove the entry from **System Settings → Privacy & Security →
Accessibility** and delete your Siri Shortcut.

---

## 7. What's next

Phase-2 ideas already noted in the PRD:

- Per-mode URL lists with Chrome **profiles** (work vs. personal)
- A daily-briefing notification (calendar + weather)
- Per-app post-launch positioning (auto-snap Slack to left quarter, etc.)
- Configurable hotkeys in the Settings window
- Apple Watch / menu bar widget complications

If any of these matter to you, open the menu, choose **Open Config…**, and
file a request right inside `config.json` as a comment — or just tell me.
