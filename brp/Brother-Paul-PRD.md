# Product Requirements Document (PRD)

**Project Name:** Brother Paul
**Tagline:** "Brother Paul, start my work."
**Version:** 1.0 (MVP)
**Date:** May 15, 2026
**Owner:** SLS
**Status:** Built & Ready

---

## 1. Problem Statement
Every morning on my MacBook I manually open the same set of work applications. This breaks focus and wastes 30–90 seconds daily. I want a **personal, native, one-command launcher** that opens my entire work environment instantly using voice or click.

---

## 2. Goals & Objectives
- Launch **Microsoft Teams, Outlook, Chrome, and Slack** (plus others) in under 3 seconds.
- Fully configurable without coding.
- Support voice command ("Brother Paul").
- Feel like a premium, native macOS application.
- Zero cost, fully local, private.

---

## 3. Target User
- Power user on MacBook (macOS Ventura+)
- Wants speed, simplicity, and ownership
- Uses voice + hotkeys regularly

---

## 4. Core Features (MVP)

| Priority | Feature                  | Description |
|----------|--------------------------|-----------|
| Must     | One-Click Launch         | Menu bar + Dock icon launches all default apps |
| Must     | Voice Command            | "Brother Paul" or "Hey Brother Paul, start work" via Siri Shortcut |
| Must     | Fully Configurable       | Edit apps via JSON or in-app Settings |
| Should   | Session Modes            | Deep Work, Meetings, Admin (different app sets) |
| Should   | Post-Launch Actions      | Hide other apps, open specific URLs |
| Could    | Pre-Launch Checklist     | Optional confirmations |
| Could    | Custom Icon & Theming    | Personal branding |

**Default Apps (MVP):**
- Microsoft Teams
- Microsoft Outlook
- Google Chrome
- Slack

---

## 5. User Flows

### Primary Flow – Voice
1. Say: **"Brother Paul"**
2. App launches → opens all 4 apps → hides other windows
3. Notification: "Good morning. Work session started."

### Primary Flow – Click
1. Click menu bar icon → "Start Full Work Session"
2. Same result as voice.

### Mode Switching
- Deep Work → Teams + Chrome + Slack + Notion
- Meetings → Teams + Outlook + Zoom
- Admin → Outlook + Chrome

---

## 6. Technical Requirements

- **Platform:** macOS (SwiftUI)
- **Language:** Swift
- **Storage:** Local `config.json` in `~/Library/Application Support/BrotherPaul/`
- **Permissions:** Accessibility (for launching apps), Speech Recognition
- **Size:** < 10 MB
- **No internet required** after build

---

## 7. Non-Functional Requirements
- Dark & Light mode support
- Beautiful, minimal UI with SF Symbols
- Fast startup (< 1 second)
- Privacy-first (no analytics, no cloud)

---

## 8. Out of Scope (MVP)
- Cross-platform support
- Cloud sync / team sharing
- AI smart suggestions
- Advanced automation (will be Phase 2)

---

## 9. Future Enhancements (Phase 2+)
- In-app visual config editor
- Open specific Chrome tabs / profiles
- Spotify playlist + Focus mode toggle
- Daily briefing (calendar + weather)
- Custom icon & sounds
- Apple Watch / menu bar widget

---

## 10. Current Implementation Status
**Completed**
- Native SwiftUI menu bar app
- Voice command via Shortcuts
- Configurable JSON + default apps
- Multiple launch modes
- Hide other applications
- Ready to build in Xcode

**Project Folder:** `BrotherPaul.xcodeproj`

---

**Approval**

Built live with Grok. Ready for daily use.

---

*Last updated: May 15, 2026*
