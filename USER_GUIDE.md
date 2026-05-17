# Brother Paul — User Guide

> "Brother Paul, start my work."

A tiny macOS menu bar app that does four things very well:

1. **Launches your work apps** with one click, one URL, or one voice command.
2. **Snaps any window** to halves, corners, or fullscreen — with keyboard
   shortcuts or by dragging to a screen edge.
3. **Surfaces a Mission Control digest** of today's upcoming events,
   priority email, and recent notifications — manually or whenever you
   start a work session.
4. **Greets you with a daily Christ-focused verse** from a 132-passage
   library spanning the Book of Mormon and the four Gospels of the KJV.

Everything is local. No accounts, no cloud, no analytics. Two optional
integrations talk to the network (Gmail and Microsoft Graph) and only
after you've explicitly configured them with your own OAuth credentials.

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
4. Name the shortcut **Brother Paul**. The shortcut's name **is** the
   phrase Siri listens for, so pick whatever you want to say — but
   "Brother Paul" matches the app and is the recommended default.
5. Enable **Use with Siri** on the shortcut.
6. Make sure **System Settings → Apple Intelligence & Siri → Listen for "Siri"
   or "Hey Siri"** is on.

Now: "Hey Siri, Brother Paul."

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

## 2.5 End your work session

The mirror of starting. Brother Paul will send a graceful Quit to every
app listed in the chosen mode — apps with unsaved work get their normal
"Save changes?" prompt; Brother Paul itself stays running so you can
re-start later.

### Click

🧠 → **End Full Session** (named after your default mode).

### Voice

Make a second Siri Shortcut for the end action, paralleling the start
shortcut you made above:

1. Open **Shortcuts.app** → **+** (or right-click your existing start
   shortcut → **Duplicate** if you'd rather edit a copy).
2. Add an **Open URLs** action with URL `brotherpaul://stop`.
3. Name the shortcut whatever you'll actually say. Short, distinctive
   words work best — examples that have worked in the wild:
   **Ciao**, **Wrap up**, **Good night**, **Sign off**. The shortcut's
   **literal name is the Siri trigger phrase**, so spell it the way Siri
   is likely to transcribe what you say. If Siri keeps mishearing,
   rename the shortcut to match its transcription.
4. Enable **Use with Siri** on the shortcut (the ⓘ details panel).
5. Confirm it appears: `shortcuts list` in Terminal.

Now: "Hey Siri, Ciao" (or whatever you named it) quits your work apps.

### Terminal

```bash
open brotherpaul://stop
open "brotherpaul://stop?mode=Meetings"
```

Note: apps you opened by hand that aren't in any mode are untouched.
Mission Control isn't closed automatically — dismiss it with **✕** if
you don't want it lingering.

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

## 3.5 Mission Control — today's digest

Click 🧠 → **Mission Control…** (or just press `⌘M` with the menu open) and
Brother Paul builds a one-pager:

```
🧠 Mission Control                        [Refresh]
─────────────────────────────────────────────────
📅 Upcoming Events  (3)
   • 10:00 – 10:30   1:1 with Mei            in 12m
   • 11:00 – 12:00   Sprint Planning         in 1h
   • 14:00 – 14:30   Vendor sync             in 4h

✉️  Priority Email  (5)
   • Outlook   "Q3 plan review"   alice@…   25m ago
   • Gmail     "FYI: prod alert"  ops-bot…  2h ago
   • …

🔔 Recent Notifications  (12)
   • Slack       "@you on #incidents"     3h ago
   • Calendar    "Sprint Planning soon"   1h ago
   • …
```

It also opens automatically when you start a session (toggle that via
`missionControl.openOnStartWork` if you'd rather it stayed quiet). When
it opens this way, Brother Paul waits a couple of seconds for your session
apps to finish launching before bringing Mission Control to the front, so
it lands on top of the launch storm instead of behind it. It's a regular
window — click another app to bring that app forward; close Mission
Control with **✕** or **⌘W** when you're done. (⌘Q does nothing here —
Brother Paul is an accessory app with no main menu, so the system has
nothing to bind ⌘Q to. Quit the whole app from 🧠 → **Quit**.)

### Setup

Each section asks for its own permission the first time it runs. You don't
have to set them all up at once — disabled sections just say "denied" or
"not configured" without breaking the rest.

| Section        | Permission you'll grant                                             |
|----------------|---------------------------------------------------------------------|
| Events         | **Calendars** — macOS prompts you on first run                      |
| Outlook        | **Automation → Microsoft Outlook** — macOS prompts on first script  |
| Gmail          | One-time **OAuth** — run `./bin/brpaul-gmail-auth.sh` (below)       |
| Notifications  | **Full Disk Access** — drag BrotherPaul.app in manually             |

### VIPs

Add senders to `missionControl.vipSenders` in your `config.json` and they
float to the top of the email section with a red priority dot. Matching is
case-insensitive substring against the **From** display name or address —
so `"Project Alpha"` flags anything from "Project Alpha Updates
<no-reply@…>" and `"@vip.example.com"` flags an entire domain.

### Outlook calendar via Microsoft Graph (recommended for Outlook users)

Microsoft removed calendar scripting from Outlook for Mac, so the AppleScript
fetcher can't pull events. Microsoft Graph is the supported path and works
regardless of which Outlook UI you're on.

1. [entra.microsoft.com](https://entra.microsoft.com) → **App registrations →
   New registration**.
   - Name: `Brother Paul`
   - Supported account types: **"Accounts in this organizational directory
     only"** if your Outlook is a work/school account, or **"any
     organizational directory + personal Microsoft accounts"** if you want it
     to work for personal Outlook too.
   - Redirect URI: leave blank for now.
   - Click **Register**.
2. In the new app → **Authentication → Add a platform → "Mobile and desktop
   applications"** → in the **Custom redirect URIs** box add
   `http://localhost:8765` → **Configure**. Scroll down, set **"Allow public
   client flows" → Yes**, then **Save**.
3. **API permissions → Add a permission → Microsoft Graph → Delegated
   permissions → Calendars.Read → Add**. If your tenant requires admin
   consent, click **Grant admin consent**.
4. On the **Overview** page, copy the **Application (client) ID**.
5. In Terminal, from this repo:
   ```bash
   ./bin/brpaul-graph-auth.sh <CLIENT_ID>
   # if your tenant SSO requires a specific tenant GUID:
   # BRPAUL_TENANT=<your-tenant-guid> ./bin/brpaul-graph-auth.sh <CLIENT_ID>
   ```
   Browser opens, you sign in with the same Microsoft account that owns the
   Outlook calendar, you consent. The script prints a JSON snippet — paste it
   into `~/Library/Application Support/BrotherPaul/config.json` under
   `missionControl` (replacing the empty `graph` block), set
   `"includeGraphCalendar": true`, and choose **Reload Config** from the menu.

After that: 🧠 → **Mission Control… → Refresh** and your Outlook events show
in the Events section.

The refresh token lives in `config.json`, never leaves your machine, and is
scoped to read-only calendar access.

### Gmail in 4 minutes

If you want Gmail in the digest (Outlook works without any setup):

1. [console.cloud.google.com](https://console.cloud.google.com) → create a
   project (or reuse one).
2. **APIs & Services → Library** → enable **Gmail API**.
3. **OAuth consent screen** → External, Testing, add yourself as a test user.
4. **Credentials** → Create credentials → **OAuth client ID** → Application
   type **Desktop app**. Copy the client ID + client secret.
5. In Terminal, from this repo:
   ```bash
   ./bin/brpaul-gmail-auth.sh <CLIENT_ID> <CLIENT_SECRET>
   ```
   Your browser opens, you sign in, you'll see a Brother Paul confirmation
   page. The script prints a JSON snippet — paste it into your `config.json`
   under `missionControl.gmail`, set `"includeGmail": true`, and choose
   **Reload Config** from the menu.

The refresh token is stored in `config.json`, not Keychain. Keep that file
to yourself.

### Verse of the Day

At the top of Mission Control you'll see a quote-card with one
Christ-focused verse from a 132-passage library:

- **61 from the Book of Mormon** (1 Nephi → Moroni)
- **71 from the four Gospels of the KJV** (Matthew, Mark, Luke, John)

Selection is **day-of-year modulo verse-count**, so the same calendar date
returns the same verse year over year — predictable rhythm, not a surprise.

**Edit / curate / replace** the library: 🧠 → **Edit Daily Verses…** opens
`~/Library/Application Support/BrotherPaul/verses.json` in your default
editor. Each entry has `reference`, `text`, and optional `source`:

```json
{
  "reference": "Mosiah 3:17",
  "source": "Book of Mormon",
  "text": "And moreover, I say unto you, that there shall be no other name given…"
}
```

Add as many entries as you like — your custom list takes priority over the
built-in defaults. A seed-version marker (`.verses-seed-version` next to
`verses.json`) lets new releases push expanded defaults; bump it to a large
number locally if you want to lock your edits against future seed refreshes.

To disable the verse card entirely, set `missionControl.includeVerseOfDay`
to `false`.

### Outlook calendar without Azure (no IT involvement)

Microsoft removed AppleScript calendar access from Outlook for Mac, so the
old "just check the toggle in Outlook" workaround no longer applies. If
your org **also** blocks Azure AD app registration (which is needed for
Microsoft Graph), there's still a way to get your Outlook calendar into
Mission Control:

1. In Outlook on the web ([outlook.office.com](https://outlook.office.com))
   → **Settings ⚙️ → Calendar → Shared calendars → Publish a calendar**.
   Pick your calendar, choose **"Can view all details"**, click **Publish**.
2. Copy the **`.ics`** URL it gives you (not the HTML one).
3. macOS **Calendar.app → File → New Calendar Subscription** → paste the URL.
4. Set auto-refresh to 5 minutes, click OK. In Calendar.app's left sidebar,
   make sure the new "Outlook" subscription's **checkbox is on**.
5. **Mission Control → Refresh**. Your events flow in through EventKit,
   no Graph, no IT ticket.

If your org has also disabled calendar publishing, only Path 2 (Microsoft
Graph) works — and only with IT cooperation. See the Graph section above.

### Notifications history needs Full Disk Access

macOS protects the notification database with FDA. To grant it:

1. **System Settings → Privacy & Security → Full Disk Access**.
2. Click **+** → choose `/Applications/BrotherPaul.app`.
3. Toggle it on. Quit + relaunch BrotherPaul.

If you'd rather skip notifications entirely, set
`missionControl.includeNotifications: false`.

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
Brother Paul") launches the Writing session.

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

**"Hey Siri, Brother Paul" doesn't trigger.**
- A Shortcut named **Brother Paul** must exist in your Shortcuts library
  (Shortcuts.app → list it with `shortcuts list` in Terminal). The shortcut
  name **is** the trigger phrase — if yours is named something else (e.g.
  "Start Work"), say that name instead, or rename it to "Brother Paul".
- The shortcut must have **Use with Siri** enabled.
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

**Mission Control's Events section is empty.**
Three independent fetchers feed Events: EventKit (Calendar.app), Outlook
AppleScript, and Microsoft Graph. Look at the status line in the section
header — it tells you which sources failed and why. Common cases:
- *"Calendar: No events in the next 24h"* → EventKit has Calendar permission
  but your calendar's events aren't visible. Open Calendar.app, confirm the
  relevant calendars have their checkboxes turned **on**.
- *"Outlook calendar … (errno -1751)"* → Microsoft removed the AppleScript
  class. Set `includeOutlookCalendar: false`, use Graph or iCal subscribe
  (section 3.5 above).
- *"Graph token refresh failed"* → your refresh token was revoked (often
  happens after password changes or admin actions). Re-run
  `./bin/brpaul-graph-auth.sh` to get a fresh token.

**The Verse of the Day says nothing or the wrong verse.**
- *Card missing entirely:* `missionControl.includeVerseOfDay` is `false` in
  your config, or your `verses.json` is empty / malformed (the Coordinator
  falls back to defaults if the file fails to decode).
- *Wrong wording:* the verse library is in
  `~/Library/Application Support/BrotherPaul/verses.json`. Open it via 🧠
  → **Edit Daily Verses…** and fix in place; next refresh picks it up.
- *Want it to never change:* duplicate the same verse 132 times, or set a
  one-element list, or hard-code your favorite at index `(day-of-year - 1)
  mod count` and bump `.verses-seed-version` to a large number to keep it.

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
