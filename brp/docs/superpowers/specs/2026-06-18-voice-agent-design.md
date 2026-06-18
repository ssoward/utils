# Brother Paul Voice Agent — Design

**Date:** 2026-06-18
**Status:** Approved design, ready for implementation planning
**Owner:** Scott Soward

> "Brother Paul, what does my afternoon look like?"

A speech-driven, conversational agent inside the Brother Paul macOS menu-bar app.
You wake it by saying **"Brother Paul"**, speak a request, and it answers aloud
(and in a floating panel) — and can act on your machine: open/close apps, run
session modes, snap windows, answer questions about your calendar and email, and
perform open-ended system actions, all gated by a tiered confirmation model.

This turns the app's current "voice command" (a Siri Shortcut firing a dumb
`brotherpaul://` URL) into a real in-app voice assistant with natural-language
understanding via Claude.

---

## 1. Goals & non-goals

### Goals
- Hands-free activation via the custom wake word **"Brother Paul"**.
- Genuine conversation ("discuss my calendar"), not a fixed command grammar —
  powered by Claude with tool use.
- Control the computer: open/close apps, start/end modes, snap windows, query
  schedule/email, and open-ended system actions (open files/URLs, AppleScript,
  shell, settings).
- Spoken replies **and** a floating conversation panel (transcript + the action
  being taken + confirm/deny buttons).
- Tiered safety: read-only and easily-reversible actions run immediately;
  destructive/irreversible/open-ended actions require confirmation.
- Reuse the existing four pillars (AppLauncher, WindowSnapper, Mission Control
  fetchers) as tool back-ends rather than rebuilding them.
- Degrade gracefully: works via a push-to-talk hotkey when the wake-word engine
  isn't configured; the whole feature is off by default.

### Non-goals (v1)
- No multi-language support (English only — Apple on-device locale).
- No Managed Agents / server-side tool execution (tools must run locally).
- No streaming TTS of partial responses (speak the final reply).
- No persistent cross-session memory of conversations.

---

## 2. Decisions (from brainstorming)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| The "brain" | **Cloud LLM (Claude)** | Enables open-ended conversation ("discuss"). |
| Activation | **Wake word "Brother Paul"** + push-to-talk fallback | The aspirational hands-free experience; fallback keeps it testable/usable without the wake engine. |
| Wake engine | **Picovoice Porcupine** (custom keyword) on-device; hotkey fallback | Reliable, low-power, true custom phrase. Apple Speech is unreliable for always-on wake spotting. |
| Speech-to-text | **Apple `SFSpeechRecognizer`, on-device** | Free, local; only final text leaves the machine. |
| Response | **Voice + floating panel** | Hands-free, but visible/clickable for confirmations and to see what AppleScript will run. |
| Capabilities | **All four**: app/session, window, calendar+email Q&A, open-ended system control | Full agentic vision, shipped in v1. |
| Safety | **Tiered**: auto-run safe, confirm risky | Balances the hands-free dream with protection against misheard/hallucinated destructive actions. |
| Model | **`claude-opus-4-8`** (configurable) | Standing default; configurable to Haiku/Sonnet for lower latency. |
| Integration | **Client-side tool use** via `/v1/messages` over `URLSession` (raw HTTPS) | Swift has no official Anthropic SDK; tools must execute locally, so Managed Agents is unsuitable. |

---

## 3. Architecture & data flow

A new **Voice** subsystem and **Agent** subsystem are wired into `AppDelegate`
alongside the existing `hotkeys` / `dragSnapper` / `missionControl` members.

```
"Brother Paul"  ──▶ WakeWordEngine (Porcupine)         [always-on, on-device]
   (or ⌃⌥-Space hotkey fallback)
        │
        ▼
VoiceSessionController  ── chime + open floating panel, start mic
        │
        ▼
SpeechTranscriber (Apple SFSpeechRecognizer, on-device) ─▶ final transcript text
        │
        ▼
ClaudeClient.send(transcript, history, tools)   ── POST /v1/messages (URLSession)
        │
        ▼
   manual tool-use loop:
     response.stop_reason == "tool_use"?
        │  ToolRiskClassifier(tool)
        │     ├─ safe  → execute now ───────────────┐
        │     └─ confirm → panel shows action + Confirm/Deny;
        │                  also spoken "Do you want me to…?"
        │                  on YES → execute ─────────┤
        │                                             ▼
        │                              ToolExecutor → AppLauncher / WindowSnapper /
        │                                             fetchers / SystemControl
        │                                             │
        │                              tool_result ◀──┘  (is_error:true on failure)
        └──────────────────── loop until stop_reason == "end_turn"
        ▼
final text ─▶ SpeechSynthesizer (AVSpeechSynthesizer, spoken) + VoicePanelView (shown)
```

Privacy posture: the wake engine processes audio **locally**; full speech-to-text
starts only **after** wake; **only the final transcript text** is sent to the
Claude API. The API key is stored in **Keychain**, never in `config.json`. The
master switch defaults **off**.

---

## 4. Components

Grouped into new directories to keep the existing flat `Sources/BrotherPaul/`
legible.

### `Sources/BrotherPaul/Voice/`
- **`WakeWordEngine.swift`** — `protocol WakeWordEngine { var onWake: () -> Void { get set }; func start(); func stop() }`. `PorcupineWakeEngine` implements it with a custom "Brother Paul" keyword. When no Porcupine access key is configured, `AppDelegate` wires the existing hotkey path to the same `onWake` callback instead.
- **`SpeechTranscriber.swift`** — wraps `SFSpeechRecognizer` with on-device recognition. `start()` / `stop()`; emits the final transcript when end-of-speech (silence) is detected. Behind `protocol SpeechTranscribing` for testing.
- **`SpeechSynthesizer.swift`** — thin `AVSpeechSynthesizer` wrapper for spoken replies and spoken confirmation prompts. Behind `protocol SpeechSynthesizing`.
- **`VoiceSessionController.swift`** — the single stateful orchestrator. State machine: `idle → listening → thinking → confirming → speaking → idle`. Owns mic lifecycle, coordinates wake → STT → agent → panel → TTS, and routes confirmation results (spoken "yes"/"no" or panel button) back into the agent loop.

### `Sources/BrotherPaul/Agent/`
- **`ClaudeClient.swift`** — `URLSession` POST to `https://api.anthropic.com/v1/messages`. Headers: `x-api-key` (from Keychain), `anthropic-version: 2023-06-01`. Holds conversation history (`messages[]`), runs the **manual** agentic loop, handles `stop_reason` (`tool_use`, `end_turn`, `refusal`, `max_tokens`, `pause_turn`). Sends `thinking:{type:"adaptive", display:"omitted"}` and `output_config.effort` from config. Prompt-caches the stable `system` + `tools` prefix (`cache_control:{type:"ephemeral"}` on the last system block) to cut per-turn cost/latency. Behind `protocol AgentBrain { func send(transcript:String) async throws -> AgentTurn }` so tests inject a mock; the HTTP transport is itself behind a seam for `ClaudeClientTests`.
- **`AgentTools.swift`** — the four tool JSON schemas (name, description, `input_schema`) and `dispatch(toolName:input:) -> ToolExecutor`. Tool descriptions are prescriptive about *when* to call each (recent Opus models reach for tools conservatively).
- **`ToolExecutor.swift`** — `protocol ToolExecutor { func execute(_ input: JSON) async -> ToolResult }`. Concrete executors:
  - `AppControlExecutor` → `AppLauncher` (open app, close app, start/end mode, hide others).
  - `WindowControlExecutor` → `WindowSnapper` + `SnapZone` (snap/move/maximize/center focused or named window).
  - `CalendarMailExecutor` → `MissionControlCoordinator` / existing fetchers (read-only schedule + email/notification query).
  - `SystemControlExecutor` → open URL/file (`NSWorkspace.open`), run AppleScript (`NSAppleScript`/`osascript`), run shell, adjust settings. The open-ended, gated executor.
- **`ToolRiskClassifier.swift`** — **pure function** `risk(forTool:input:) -> Risk` where `Risk = .safe | .confirm`. Single source of truth for the tiered model, plus a hardcoded always-confirm/deny list for destructive shell patterns (`rm -rf`, `sudo`, `mkfs`, disk ops). Trivially unit-testable.

### `Sources/BrotherPaul/` (UI)
- **`VoicePanelWindow.swift`** — `NSWindow`/`NSPanel` wrapper (always-on-top, non-activating accessory panel), mirroring `MissionControlWindow`.
- **`VoicePanelView.swift`** — SwiftUI: live transcript, the action being taken, Confirm/Deny buttons for `.confirm`-tier steps, and the spoken reply rendered as text. A clear "listening" indicator while the mic is live.

### Wiring
- `AppDelegate` gains a `@MainActor private lazy var voiceSession = VoiceSessionController(...)`, started/stopped by `applyVoiceConfig()` (parallel to `applySnapConfig()`), based on `config.voice.enabled` and permission state.

---

## 5. Tool surface

Four tools, mapping to the four chosen capabilities:

| Tool | Back-end | Example input | Risk tier |
|------|----------|---------------|-----------|
| `control_apps` | `AppLauncher` | `{action:"start_mode", mode:"Deep Work"}`, `{action:"close_app", app:"Slack"}`, `{action:"open_app", app:"Notion"}` | open/start = **safe**; quit/close = **confirm** |
| `control_windows` | `WindowSnapper` + `SnapZone` | `{zone:"leftHalf", app:"Google Chrome"}`, `{zone:"maximize"}` | **safe** (reversible) |
| `query_schedule` | `MissionControlCoordinator` fetchers | `{sources:["calendar","email"], lookbackHours:8}` | **safe** (read-only) |
| `run_system_action` | `SystemControlExecutor` | `{kind:"open_url", payload:"https://…"}`, `{kind:"applescript", payload:"…"}`, `{kind:"shell", payload:"…"}` | `open_url`/`open_file` = **safe**; `applescript`/`shell`/settings = **confirm** (subject to deny-list) |

`run_system_action` is enabled only when `voice.allowSystemControl` is true.

---

## 6. Configuration & permissions

New `VoiceConfig` in `Models.swift`, decoded with the same
`decodeIfPresent ?? default` pattern as `MissionControlConfig` so existing
`config.json` files keep decoding (missing `voice` block → defaults, written back
on next save).

```jsonc
"voice": {
  "enabled": false,                 // master switch; OFF by default
  "model": "claude-opus-4-8",       // configurable; Haiku/Sonnet lower latency
  "effort": "medium",               // low = snappiest command routing
  "maxTokens": 1024,
  "wakeWord": {
    "enabled": true,
    "porcupineAccessKey": "",       // Picovoice access key (free tier for personal use)
    "keywordPath": ""               // path to the trained "Brother Paul" .ppn
  },
  "pushToTalkFallback": true,        // ⌃⌥-Space when no Porcupine key
  "speakReplies": true,
  "allowSystemControl": true,        // gate for run_system_action
  "confirmTier": "tiered"            // tiered | confirmEverything | trust
}
```

- **API key**: stored in **Keychain** under a Brother Paul service key. A helper
  `bin/brpaul-anthropic-auth.sh` (or a Settings field) writes it. `ClaudeClient`
  reads it at request time. Never serialized to `config.json`.
- **New `Info.plist` usage descriptions**: `NSMicrophoneUsageDescription`,
  `NSSpeechRecognitionUsageDescription`. Accessibility (window control) and
  Automation (AppleScript) are **already** requested by the app.
- **Menu additions** (`MenuBarController`): "Enable Voice Agent" toggle,
  "Voice Settings…", a live status line (listening / thinking / error), and a
  mic/speech-permission helper item — mirroring the existing Snap submenu.

---

## 7. Error handling & safety

- **No API key / no network** → spoken + panel error; session ends cleanly
  (mirrors how Mission Control surfaces missing sources).
- **Mic or Speech permission denied** → panel links to the correct System
  Settings pane.
- **Empty / low-confidence transcript** → "Sorry, I didn't catch that" and
  re-listen once, then idle.
- **Tool execution failure** → returned to Claude as a `tool_result` with
  `is_error:true` so it can adapt or report — never a silent failure.
- **`stop_reason:"refusal"`** → speak/show the refusal; do not blindly retry.
- **`max_tokens`** → speak what arrived; note truncation.
- **Confirmation**: `.confirm`-tier tools block on a spoken "yes"/"no" or a panel
  button before executing. The deny-list (`rm -rf`, `sudo`, disk ops) is always
  confirm regardless of tier (except `confirmEverything`, which confirms all).
- **Privacy**: always-on audio is processed locally by the wake engine; full STT
  starts only after wake; the panel shows a clear listening indicator; master
  switch defaults off.

---

## 8. Testing strategy

Follows the existing `Tests/BrotherPaulTests` pure-logic pattern. Hardware-bound
pieces sit behind protocols and are covered by a documented manual smoke test
(as snapping/AX already are).

- **`ToolRiskClassifierTests`** — exhaustive safe/confirm/deny classification
  across all tools and inputs, including deny-list patterns.
- **`AgentToolsTests`** — tool schema shape + `dispatch` routes each tool name to
  the correct executor (executors mocked).
- **`ClaudeClientTests`** — the manual tool-use loop against a **mocked
  transport**: canned `tool_use → tool_result → end_turn` sequences; verifies
  history assembly, multi-tool turns, and `stop_reason` handling. No live API.
- **`VoiceSessionControllerTests`** — state-machine transitions with mock
  wake/STT/brain/TTS, including the confirmation branch and the re-listen path.
- **Manual smoke test** (documented in `bin/`) — Porcupine wake,
  `SFSpeechRecognizer`, and `AVSpeechSynthesizer` exercised end-to-end on real
  hardware, since they can't run headless.

---

## 9. Open implementation notes

- **Latency**: Opus 4.8 is the default; document that `claude-haiku-4-5` or
  `claude-sonnet-4-6` materially reduce voice round-trip latency, and that
  `effort:"low"` is recommended for snappy command routing.
- **Porcupine licensing**: free tier covers personal use; commercial
  distribution requires a paid Picovoice plan — call this out in the README.
- **Prompt caching**: the system prompt + tool definitions are stable across a
  conversation, so cache that prefix to reduce cost and time-to-first-token.
- **`pause_turn`**: handle by re-sending per the manual-loop pattern (relevant if
  server-side tools are ever added; not in v1).
