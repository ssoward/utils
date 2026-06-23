# Voice Agent — Plan 2b: Hardware, UI & Wiring Roadmap

> **For agentic workers:** This plan is NOT for the automated subagent+TDD loop. Most tasks touch the microphone, audio output, an external dependency (Porcupine), SwiftUI windows, and `Info.plist` permissions — none of which can be verified headlessly with `swift test`. Execute it as a **guided manual build on a real Mac**, with the human running each task's **Manual Verification** block and confirming before moving on. The few pure-logic helpers still get unit tests. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Implement the four Plan-2a protocol seams with real hardware/UI — Porcupine wake word ("Brother Paul") + push-to-talk hotkey fallback, Apple on-device speech-to-text, text-to-speech, and a floating SwiftUI conversation panel — then wire `VoiceSessionController` into the running app via `AppDelegate`, add the menu items, `Info.plist` usage strings, and a Keychain API-key helper. The result is a working, hands-free voice agent.

**Architecture:** Each concrete type implements one Plan-2a seam (`WakeWordEngine`, `SpeechTranscribing`, `SpeechSynthesizing`, `VoiceUI`) and is injected into `VoiceSessionController`. The controller is constructed once in `AppDelegate` (parallel to the existing `hotkeys` / `missionControl` members), gated by `config.voice.enabled`. Confirmation routes through the tier policy already merged in 2a: the `ClaudeClient` is built with `needsConfirmation: { ConfirmationPolicy.requiresConfirmation(for: $0, tierString: config.voice.confirmTier) }`, and the panel/voice `requestConfirmation` is the user-facing blocker. No agent-core logic changes — 2b is pure I/O and wiring on top of the merged 2a seams.

**Tech Stack:** Swift 5.9+, AppKit, SwiftUI, `Speech` (SFSpeechRecognizer), `AVFoundation` (AVSpeechSynthesizer + AVAudioEngine), `Security` (Keychain, already used), Carbon (hotkey, existing pattern), and the **Picovoice Porcupine** Swift package (new SPM dependency). Builds on merged Plans 1 + 2a.

## Global Constraints

- Platform: macOS 13+. Real Mac required for verification (mic + audio).
- **The whole feature stays behind `config.voice.enabled` (default `false`).** A user who never enables voice sees zero behavior change and gets no permission prompts.
- **Confirmation must route through the 2a policy.** Construct `ClaudeClient` with `needsConfirmation: { ConfirmationPolicy.requiresConfirmation(for: $0, tierString: config.voice.confirmTier) }`. The `VoiceUI.requestConfirmation` blocker and this gate must reference the same `confirmTier` — do not hardcode a tier in either place. (2a final-review carry-forward #1.)
- **Wake callbacks may arrive off the main thread.** `VoiceSessionController` already hops via `Task { @MainActor }`, so engines may fire `onWake` from any thread. Do NOT add `MainActor.assumeIsolated` anywhere. (2a carry-forward #2.)
- API key: read from `KeychainSecretStore` under `SecretKey.anthropicAPIKey` (both from Plan 1). Never in `config.json`.
- New `Info.plist` keys: `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`.
- Porcupine is optional at runtime: if `config.voice.wakeWord.porcupineAccessKey` / `keywordPath` are empty, the app uses the **push-to-talk hotkey fallback** and never references the Porcupine SDK at runtime. The SPM dependency is still linked, but a missing key must degrade gracefully (no crash).
- Follow existing style: four-space indent, `NSLog("BrotherPaul: …")`, `enum` namespaces for stateless helpers, protocol-per-seam.
- Each task ends with a commit. Pure-logic helpers get `XCTest` coverage in `Tests/BrotherPaulTests/`; hardware/UI tasks get a documented Manual Verification block instead.

---

### Task 1: Keychain API-key helper (CLI + menu entry point)

**Type:** Mostly logic; manually verified end-to-end.

**Files:**
- Create: `brp/bin/brpaul-anthropic-auth.sh`
- Modify: `brp/Sources/BrotherPaul/MenuBarController.swift` (add a "Set Anthropic API Key…" item, shown only when voice is enabled)
- Test: none new (Keychain round-trip can't run headless — covered by Plan 1's `SecretStoreTests` for the in-memory path + this task's Manual Verification for the real Keychain path).

**Interfaces:**
- Produces: a shell helper that writes the key into the login Keychain under the same service/account `KeychainSecretStore` reads (`service = "com.brotherpaul.secrets"`, `account = "anthropic-api-key"`), and a menu item that prompts for the key via an `NSAlert` + secure text field and stores it via `KeychainSecretStore().set(_:for:)`.

- [ ] **Step 1: Write the shell helper**

```bash
#!/usr/bin/env bash
# brp/bin/brpaul-anthropic-auth.sh — store the Anthropic API key in the login Keychain
# so BrotherPaul's KeychainSecretStore can read it. Usage: ./brpaul-anthropic-auth.sh <API_KEY>
set -euo pipefail
KEY="${1:-}"
if [ -z "$KEY" ]; then
  read -r -s -p "Anthropic API key: " KEY; echo
fi
SERVICE="com.brotherpaul.secrets"
ACCOUNT="anthropic-api-key"
# -U updates if present; generic password matches KeychainSecretStore's query.
security add-generic-password -U -s "$SERVICE" -a "$ACCOUNT" -w "$KEY"
echo "Stored Anthropic API key for BrotherPaul ($SERVICE/$ACCOUNT)."
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x brp/bin/brpaul-anthropic-auth.sh`

- [ ] **Step 3: Add the menu item**

In `MenuBarController.swift`, in the menu-build section, add (only when `ConfigManager.shared.config.voice.enabled`):
```swift
let setKey = NSMenuItem(title: "Set Anthropic API Key…", action: #selector(promptForAPIKey), keyEquivalent: "")
setKey.target = self
menu.addItem(setKey)
```
And the handler:
```swift
@objc private func promptForAPIKey() {
    let alert = NSAlert()
    alert.messageText = "Anthropic API Key"
    alert.informativeText = "Stored securely in your Keychain. Used by Brother Paul's voice agent."
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")
    let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
    alert.accessoryView = field
    if alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty {
        KeychainSecretStore().set(field.stringValue, for: SecretKey.anthropicAPIKey)
        NSLog("BrotherPaul: stored Anthropic API key in Keychain")
    }
}
```

- [ ] **Step 4: Build**

Run: `cd brp && swift build`
Expected: builds cleanly.

- [ ] **Manual Verification**
  1. `./brp/bin/brpaul-anthropic-auth.sh sk-ant-test123` → prints "Stored…".
  2. `security find-generic-password -s com.brotherpaul.secrets -a anthropic-api-key -w` → prints `sk-ant-test123`.
  3. (After Task 7 wiring exists) the menu item appears only when voice is enabled, and saving a key via the dialog updates the Keychain entry.
  4. Clean up the test key: `security delete-generic-password -s com.brotherpaul.secrets -a anthropic-api-key`.

- [ ] **Step 5: Commit**

```bash
git add brp/bin/brpaul-anthropic-auth.sh brp/Sources/BrotherPaul/MenuBarController.swift
git commit -m "feat(brp): Keychain API-key helper (CLI + menu) for the voice agent"
```

---

### Task 2: SpeechSynthesizing — AVSpeechSynthesizer

**Type:** Hardware (audio out). Manually verified.

**Files:**
- Create: `brp/Sources/BrotherPaul/Voice/SystemSpeechSynthesizer.swift`

**Interfaces:**
- Consumes: `SpeechSynthesizing` (Voice/VoiceSeams.swift).
- Produces: `@MainActor final class SystemSpeechSynthesizer: SpeechSynthesizing` wrapping `AVSpeechSynthesizer`; `speak(_:)` enqueues an utterance; `stop()` cancels immediately.

- [ ] **Step 1: Implement**

```swift
// brp/Sources/BrotherPaul/Voice/SystemSpeechSynthesizer.swift
import AVFoundation

@MainActor
final class SystemSpeechSynthesizer: SpeechSynthesizing {
    private let synth = AVSpeechSynthesizer()

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(utterance)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
    }
}
```

- [ ] **Step 2: Build**

Run: `cd brp && swift build`
Expected: builds cleanly.

- [ ] **Manual Verification** (needs a tiny temporary harness or wait until Task 7 wiring): construct `SystemSpeechSynthesizer()` and call `speak("Brother Paul is online.")` — confirm it speaks aloud through the default output device, and that a second `speak` call while the first is talking queues rather than crashes. `stop()` cuts speech off mid-word.

- [ ] **Step 3: Commit**

```bash
git add brp/Sources/BrotherPaul/Voice/SystemSpeechSynthesizer.swift
git commit -m "feat(brp): AVSpeechSynthesizer-backed SpeechSynthesizing"
```

---

### Task 3: SpeechTranscribing — SFSpeechRecognizer (on-device)

**Type:** Hardware (mic + Speech permission). Manually verified.

**Files:**
- Create: `brp/Sources/BrotherPaul/Voice/AppleSpeechTranscriber.swift`
- Modify: `brp/Resources/Info.plist` (add `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`)

**Interfaces:**
- Consumes: `SpeechTranscribing` (Voice/VoiceSeams.swift).
- Produces: `@MainActor final class AppleSpeechTranscriber: SpeechTranscribing`. `startListening(onFinal:)` requests authorization (first run), starts an `AVAudioEngine` tap feeding an on-device `SFSpeechRecognitionRequest` (`requiresOnDeviceRecognition = true`), and calls `onFinal` once with the final transcript when the recognizer reports `isFinal` or a short trailing-silence timer fires. `stop()` tears down the audio tap, engine, and request. Authorization failure → `onFinal("")` (the controller treats empty as "didn't catch").

- [ ] **Step 1: Add Info.plist usage strings**

In `brp/Resources/Info.plist`, add:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Brother Paul listens to your spoken request after you say the wake word.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Brother Paul transcribes your request on-device to understand what to do.</string>
```

- [ ] **Step 2: Implement the transcriber**

```swift
// brp/Sources/BrotherPaul/Voice/AppleSpeechTranscriber.swift
import Foundation
import Speech
import AVFoundation

@MainActor
final class AppleSpeechTranscriber: SpeechTranscribing {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onFinal: ((String) -> Void)?
    private var silenceTimer: Timer?
    private var latest: String = ""

    func startListening(onFinal: @escaping (String) -> Void) {
        self.onFinal = onFinal
        self.latest = ""

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                guard status == .authorized, let recognizer = self.recognizer, recognizer.isAvailable else {
                    self.deliver("")   // not authorized / unavailable → "didn't catch"
                    return
                }
                self.beginCapture(recognizer: recognizer)
            }
        }
    }

    private func beginCapture(recognizer: SFSpeechRecognizer) {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        audioEngine.prepare()
        do { try audioEngine.start() } catch {
            NSLog("BrotherPaul: audio engine failed — %@", error.localizedDescription)
            deliver(""); return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result = result {
                    self.latest = result.bestTranscription.formattedString
                    self.resetSilenceTimer()
                    if result.isFinal { self.deliver(self.latest) }
                }
                if error != nil { self.deliver(self.latest) }
            }
        }
        resetSilenceTimer()
    }

    /// End the turn after ~1.2s of no new partials (natural end of speech).
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.deliver(self?.latest ?? "") }
        }
    }

    private func deliver(_ text: String) {
        guard let cb = onFinal else { return }
        onFinal = nil          // deliver exactly once per turn
        stop()
        cb(text)
    }

    func stop() {
        silenceTimer?.invalidate(); silenceTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
    }
}
```

- [ ] **Step 3: Build**

Run: `cd brp && swift build`
Expected: builds cleanly.

- [ ] **Manual Verification** (must run as the bundled `.app`, not `swift run` — permission prompts require a bundle): build the app (Task 8 wiring or `build-app.sh`), trigger listening, grant mic + Speech permission on first run, speak "what time is it", confirm `onFinal` fires once with the transcript ~1 s after you stop talking. Verify denying permission yields a single `onFinal("")`. Confirm on-device mode (no network needed for STT).

- [ ] **Step 4: Commit**

```bash
git add brp/Sources/BrotherPaul/Voice/AppleSpeechTranscriber.swift brp/Resources/Info.plist
git commit -m "feat(brp): on-device SFSpeechRecognizer transcriber + mic/speech usage strings"
```

---

### Task 4: WakeWordEngine — hotkey fallback (no dependency)

**Type:** Logic + Carbon hotkey (existing pattern). Manually verified.

**Files:**
- Create: `brp/Sources/BrotherPaul/Voice/HotkeyWakeEngine.swift`

**Interfaces:**
- Consumes: `WakeWordEngine` (Voice/VoiceSeams.swift), Carbon (mirror `HotkeyManager`'s `RegisterEventHotKey` plumbing).
- Produces: `final class HotkeyWakeEngine: WakeWordEngine` that registers a single global push-to-talk hotkey (⌃⌥-Space) and fires `onWake?()` when pressed. This is the always-available fallback when Porcupine isn't configured. `onWake` may be invoked from the Carbon handler thread — that's fine (the controller hops to the main actor).

- [ ] **Step 1: Implement**

Model the Carbon plumbing on the existing `HotkeyManager.swift` (same `RegisterEventHotKey` / `InstallEventHandler` / C-callback pattern), but register ONE hotkey (keyCode `kVK_Space`, modifiers `controlKey | optionKey`, a distinct signature e.g. `'BPWK'`) whose handler calls `onWake?()`.

```swift
// brp/Sources/BrotherPaul/Voice/HotkeyWakeEngine.swift
import AppKit
import Carbon

/// Push-to-talk wake fallback: ⌃⌥-Space fires onWake. Used when Porcupine
/// isn't configured. The Carbon handler may run off the main thread; the
/// VoiceSessionController hops to the main actor, so firing from here is safe.
final class HotkeyWakeEngine: WakeWordEngine {
    var onWake: (() -> Void)?

    private let modifiers = UInt32(controlKey | optionKey)
    private let signature: OSType = 0x4250574B // 'BPWK'
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var installed = false

    func start() {
        guard !installed else { return }
        installed = true
        installHandler()
        let id = EventHotKeyID(signature: signature, id: 1)
        RegisterEventHotKey(UInt32(kVK_Space), modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func stop() {
        if let r = hotKeyRef { UnregisterEventHotKey(r); hotKeyRef = nil }
        if let h = handlerRef { RemoveEventHandler(h); handlerRef = nil }
        installed = false
    }

    fileprivate func fire() { onWake?() }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), wakeHotkeyCallback, 1, &spec, selfPtr, &handlerRef)
    }
}

private let wakeHotkeyCallback: EventHandlerUPP = { _, _, userData in
    guard let userData = userData else { return noErr }
    Unmanaged<HotkeyWakeEngine>.fromOpaque(userData).takeUnretainedValue().fire()
    return noErr
}
```

- [ ] **Step 2: Build**

Run: `cd brp && swift build`
Expected: builds cleanly.

- [ ] **Manual Verification** (after Task 8 wiring): with no Porcupine key configured, press ⌃⌥-Space → the listening panel appears (`onWake` fired). Confirm the existing snap hotkeys (⌃⌥-arrows) still work — no signature/keycode collision.

- [ ] **Step 3: Commit**

```bash
git add brp/Sources/BrotherPaul/Voice/HotkeyWakeEngine.swift
git commit -m "feat(brp): push-to-talk hotkey wake fallback (Carbon ⌃⌥-Space)"
```

---

### Task 5: Add the Porcupine SPM dependency + PorcupineWakeEngine

**Type:** External dependency + hardware (always-on mic). Manually verified.

**Files:**
- Modify: `brp/Package.swift` (add the Porcupine product dependency)
- Create: `brp/Sources/BrotherPaul/Voice/PorcupineWakeEngine.swift`

**Interfaces:**
- Consumes: `WakeWordEngine`, the Picovoice `Porcupine` Swift package.
- Produces: `final class PorcupineWakeEngine: WakeWordEngine` constructed with `accessKey` + `keywordPath`; `start()` boots `PorcupineManager` listening for the custom "Brother Paul" keyword and fires `onWake?()` on detection; `stop()` halts it. A failed init (bad key / missing `.ppn`) logs and leaves `onWake` un-fired — the caller (Task 7) falls back to the hotkey engine.

- [ ] **Step 1: Add the dependency to Package.swift**

```swift
// in Package.swift
dependencies: [
    .package(url: "https://github.com/Picovoice/porcupine.git", from: "3.0.0")
],
// and in the BrotherPaul target:
.executableTarget(
    name: "BrotherPaul",
    dependencies: [.product(name: "Porcupine", package: "porcupine")],
    path: "Sources/BrotherPaul"
),
```
Run: `cd brp && swift package resolve` then `swift build`.
Expected: package resolves and builds. (Verify the exact product/package name against the Picovoice Swift SPM README — adjust the `.product(name:…)`/version if the published names differ. This is the one task whose exact symbols must be confirmed against the live SDK, not guessed.)

- [ ] **Step 2: Implement the engine**

```swift
// brp/Sources/BrotherPaul/Voice/PorcupineWakeEngine.swift
import Foundation
import Porcupine

/// On-device "Brother Paul" wake-word detection via Picovoice Porcupine.
/// Fires onWake from Porcupine's audio callback (background thread) — safe,
/// because VoiceSessionController hops to the main actor.
final class PorcupineWakeEngine: WakeWordEngine {
    var onWake: (() -> Void)?

    private let accessKey: String
    private let keywordPath: String
    private var manager: PorcupineManager?

    init(accessKey: String, keywordPath: String) {
        self.accessKey = accessKey
        self.keywordPath = keywordPath
    }

    func start() {
        do {
            manager = try PorcupineManager(
                accessKey: accessKey,
                keywordPath: keywordPath,
                onDetection: { [weak self] _ in self?.onWake?() }
            )
            try manager?.start()
        } catch {
            NSLog("BrotherPaul: Porcupine failed to start — %@", error.localizedDescription)
            manager = nil
        }
    }

    func stop() {
        try? manager?.stop()
        manager = nil
    }

    /// True only if the engine actually started (used by AppDelegate to decide fallback).
    var isRunning: Bool { manager != nil }
}
```
(Confirm `PorcupineManager`'s exact initializer signature and the detection-callback shape against the Picovoice Swift docs — adjust the closure/labels to match. The `isRunning` flag is the signal Task 7 uses to fall back to the hotkey engine.)

- [ ] **Step 3: Build**

Run: `cd brp && swift build`
Expected: builds cleanly.

- [ ] **Manual Verification** (needs a Picovoice access key + a trained "Brother Paul" `.ppn`): set `config.voice.wakeWord.porcupineAccessKey` and `keywordPath`, run the app, say "Brother Paul" → the listening panel appears. Say unrelated speech → no false trigger within a reasonable window. Confirm a bad/empty key logs the error and does NOT crash (Task 7 then uses the hotkey).

- [ ] **Step 4: Commit**

```bash
git add brp/Package.swift brp/Package.resolved brp/Sources/BrotherPaul/Voice/PorcupineWakeEngine.swift
git commit -m "feat(brp): Porcupine wake-word engine + SPM dependency"
```

---

### Task 6: VoiceUI — floating SwiftUI conversation panel

**Type:** UI. Manually verified; the view-model mapping gets a unit test.

**Files:**
- Create: `brp/Sources/BrotherPaul/Voice/VoicePanelModel.swift` (observable view model — testable)
- Create: `brp/Sources/BrotherPaul/Voice/VoicePanelView.swift` (SwiftUI view)
- Create: `brp/Sources/BrotherPaul/Voice/VoicePanelWindow.swift` (NSPanel host + `VoiceUI` conformance)
- Test: `brp/Tests/BrotherPaulTests/VoicePanelModelTests.swift`

**Interfaces:**
- Consumes: `VoiceUI`, `VoiceUIState`, `ToolCall` (Voice/VoiceSeams.swift, Agent).
- Produces:
  - `@MainActor final class VoicePanelModel: ObservableObject` with `@Published var state: VoiceUIState`, `@Published var confirmContinuation` plumbing, and a pure `static func summary(for state: VoiceUIState) -> String` (the human-readable line the panel shows — unit-tested).
  - `struct VoicePanelView: View` rendering the model (transcript, action, Confirm/Deny buttons when `.confirming`).
  - `@MainActor final class VoicePanelWindow: NSObject, VoiceUI` hosting the view in a non-activating always-on-top `NSPanel`; `show(_:)` updates the model and shows/hides the panel; `requestConfirmation(_:)` shows the buttons and suspends until the user taps (via a `CheckedContinuation`), returning the bool.

- [ ] **Step 1: Write the failing test for the pure summary mapping**

```swift
// brp/Tests/BrotherPaulTests/VoicePanelModelTests.swift
import XCTest
@testable import BrotherPaul

@MainActor
final class VoicePanelModelTests: XCTestCase {
    func testSummaryStrings() {
        XCTAssertEqual(VoicePanelModel.summary(for: .idle), "")
        XCTAssertEqual(VoicePanelModel.summary(for: .listening), "Listening…")
        XCTAssertEqual(VoicePanelModel.summary(for: .thinking("what's next")), "“what's next”")
        XCTAssertEqual(VoicePanelModel.summary(for: .replied("Done.")), "Done.")
        XCTAssertEqual(VoicePanelModel.summary(for: .error("nope")), "nope")
        let call = ToolCall(id: "1", name: "control_apps",
                            input: ["action": .string("close_app"), "app": .string("Slack")])
        XCTAssertTrue(VoicePanelModel.summary(for: .confirming(call)).lowercased().contains("control_apps"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd brp && swift test --filter VoicePanelModelTests`
Expected: FAIL to compile — `VoicePanelModel` undefined.

- [ ] **Step 3: Implement the model, view, and window**

```swift
// brp/Sources/BrotherPaul/Voice/VoicePanelModel.swift
import SwiftUI

@MainActor
final class VoicePanelModel: ObservableObject {
    @Published var state: VoiceUIState = .idle
    /// Set while a confirmation is pending; the buttons resolve it.
    var onConfirm: ((Bool) -> Void)?

    static func summary(for state: VoiceUIState) -> String {
        switch state {
        case .idle:                return ""
        case .listening:           return "Listening…"
        case .thinking(let t):     return "“\(t)”"
        case .confirming(let c):   return "Run \(c.name)?"
        case .replied(let r):      return r
        case .error(let e):        return e
        }
    }

    var isConfirming: Bool { if case .confirming = state { return true }; return false }
}
```

```swift
// brp/Sources/BrotherPaul/Voice/VoicePanelView.swift
import SwiftUI

struct VoicePanelView: View {
    @ObservedObject var model: VoicePanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Brother Paul").font(.headline)
            Text(VoicePanelModel.summary(for: model.state))
                .font(.body).fixedSize(horizontal: false, vertical: true)
            if model.isConfirming {
                HStack {
                    Button("Deny")  { model.onConfirm?(false) }
                    Button("Confirm") { model.onConfirm?(true) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }
}
```

```swift
// brp/Sources/BrotherPaul/Voice/VoicePanelWindow.swift
import AppKit
import SwiftUI

@MainActor
final class VoicePanelWindow: NSObject, VoiceUI {
    private let model = VoicePanelModel()
    private lazy var panel: NSPanel = {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 140),
                        styleMask: [.titled, .nonactivatingPanel, .hudWindow],
                        backing: .buffered, defer: true)
        p.title = "Brother Paul"
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.contentView = NSHostingView(rootView: VoicePanelView(model: model))
        return p
    }()

    func show(_ state: VoiceUIState) {
        model.state = state
        switch state {
        case .idle:
            panel.orderOut(nil)
        default:
            positionTopRight()
            panel.orderFrontRegardless()
        }
    }

    func requestConfirmation(_ call: ToolCall) async -> Bool {
        await withCheckedContinuation { continuation in
            model.onConfirm = { [weak self] approved in
                self?.model.onConfirm = nil
                continuation.resume(returning: approved)
            }
        }
    }

    private func positionTopRight() {
        guard let screen = NSScreen.main else { return }
        let v = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: v.maxX - size.width - 20, y: v.maxY - size.height - 20))
    }
}
```

- [ ] **Step 4: Run the test**

Run: `cd brp && swift test --filter VoicePanelModelTests`
Expected: PASS. (Adjust the `.confirming` summary assertion if you change the wording — keep the test and code in sync.)

- [ ] **Step 5: Build**

Run: `cd brp && swift build`
Expected: builds cleanly.

- [ ] **Manual Verification** (after Task 7 wiring): trigger a turn → panel appears top-right showing "Listening…", then the transcript, then the reply, then disappears on idle. For a risky action ("close Slack"), the Confirm/Deny buttons appear and tapping resolves the action (Deny → not executed). Panel never steals focus from the active app (non-activating).

- [ ] **Step 6: Commit**

```bash
git add brp/Sources/BrotherPaul/Voice/VoicePanelModel.swift brp/Sources/BrotherPaul/Voice/VoicePanelView.swift brp/Sources/BrotherPaul/Voice/VoicePanelWindow.swift brp/Tests/BrotherPaulTests/VoicePanelModelTests.swift
git commit -m "feat(brp): floating SwiftUI voice panel (VoiceUI) + tested view model"
```

---

### Task 7: VoiceCoordinator — assemble the controller with the tier policy

**Type:** Wiring/assembly. Logic-testable for the engine-selection decision.

**Files:**
- Create: `brp/Sources/BrotherPaul/Voice/VoiceCoordinator.swift`
- Test: `brp/Tests/BrotherPaulTests/VoiceCoordinatorTests.swift`

**Interfaces:**
- Consumes: every concrete type from Tasks 2–6, plus `ClaudeClient`, `URLSessionTransport`, `KeychainSecretStore`, `AgentToolRegistry`, `AgentTools`, `ConfirmationPolicy`, `VoiceConfig`, `VoiceSessionController`.
- Produces:
  - `enum VoiceCoordinator { static func makeWakeEngine(_ cfg: VoiceConfig) -> WakeWordEngine }` — a **pure decision** (testable): returns a `PorcupineWakeEngine` when `cfg.wakeWord.enabled` and both `porcupineAccessKey` and `keywordPath` are non-empty; otherwise a `HotkeyWakeEngine`.
  - `@MainActor final class VoiceController { init(config: VoiceConfig); func start(); func stop() }` — builds the `ClaudeClient` (transport = `URLSessionTransport(secrets:)`, `needsConfirmation: { ConfirmationPolicy.requiresConfirmation(for: $0, tierString: config.confirmTier) }`), the `AgentToolRegistry(allowSystemControl:)`, the panel, transcriber, synthesizer, and wake engine, then constructs and starts a `VoiceSessionController`. If a `PorcupineWakeEngine` fails to start (`isRunning == false`), it swaps in a `HotkeyWakeEngine` so voice still works.

- [ ] **Step 1: Write the failing test for the pure engine-selection decision**

```swift
// brp/Tests/BrotherPaulTests/VoiceCoordinatorTests.swift
import XCTest
@testable import BrotherPaul

final class VoiceCoordinatorTests: XCTestCase {
    private func cfg(enabled: Bool, key: String, path: String) -> VoiceConfig {
        var v = VoiceConfig.default
        v.wakeWord = VoiceWakeWordConfig(enabled: enabled, porcupineAccessKey: key, keywordPath: path)
        return v
    }

    func testPicksHotkeyWhenWakeDisabled() {
        let e = VoiceCoordinator.makeWakeEngine(cfg(enabled: false, key: "k", path: "p"))
        XCTAssertTrue(e is HotkeyWakeEngine)
    }
    func testPicksHotkeyWhenKeyMissing() {
        let e = VoiceCoordinator.makeWakeEngine(cfg(enabled: true, key: "", path: "p"))
        XCTAssertTrue(e is HotkeyWakeEngine)
    }
    func testPicksHotkeyWhenKeywordPathMissing() {
        let e = VoiceCoordinator.makeWakeEngine(cfg(enabled: true, key: "k", path: ""))
        XCTAssertTrue(e is HotkeyWakeEngine)
    }
    func testPicksPorcupineWhenFullyConfigured() {
        let e = VoiceCoordinator.makeWakeEngine(cfg(enabled: true, key: "k", path: "p"))
        XCTAssertTrue(e is PorcupineWakeEngine)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd brp && swift test --filter VoiceCoordinatorTests`
Expected: FAIL to compile — `VoiceCoordinator` undefined.

- [ ] **Step 3: Implement**

```swift
// brp/Sources/BrotherPaul/Voice/VoiceCoordinator.swift
import Foundation

enum VoiceCoordinator {
    /// Pure decision: Porcupine only when fully configured, else the hotkey fallback.
    static func makeWakeEngine(_ cfg: VoiceConfig) -> WakeWordEngine {
        let w = cfg.wakeWord
        if w.enabled, !w.porcupineAccessKey.isEmpty, !w.keywordPath.isEmpty {
            return PorcupineWakeEngine(accessKey: w.porcupineAccessKey, keywordPath: w.keywordPath)
        }
        return HotkeyWakeEngine()
    }
}

@MainActor
final class VoiceController {
    private let session: VoiceSessionController
    private let wake: WakeWordEngine

    init(config: VoiceConfig) {
        let secrets = KeychainSecretStore()
        let transport = URLSessionTransport(secrets: secrets)
        let brain = ClaudeClient(
            config: config,
            tools: AgentTools.definitions(),
            systemPrompt: AgentTools.systemPrompt,
            secrets: secrets,
            transport: transport,
            needsConfirmation: { ConfirmationPolicy.requiresConfirmation(for: $0, tierString: config.confirmTier) }
        )
        let registry = AgentToolRegistry(allowSystemControl: config.allowSystemControl)
        let ui = VoicePanelWindow()
        let transcriber = AppleSpeechTranscriber()
        let synthesizer = SystemSpeechSynthesizer()

        var engine = VoiceCoordinator.makeWakeEngine(config)
        // If Porcupine is selected but can't start, fall back to the hotkey.
        if let porcupine = engine as? PorcupineWakeEngine {
            porcupine.start()
            if !porcupine.isRunning { engine = HotkeyWakeEngine() }
        }
        self.wake = engine

        self.session = VoiceSessionController(
            wake: engine, transcriber: transcriber, synthesizer: synthesizer,
            brain: brain, registry: registry, ui: ui, speakReplies: config.speakReplies)
    }

    func start() { session.start() }
    func stop() { session.stop() }
}
```
(Note: `session.start()` installs the wake callback and calls `wake.start()`. Porcupine's pre-start above is only to test `isRunning` for the fallback; ensure `start()` is idempotent — `PorcupineWakeEngine.start()` guards on `manager == nil`, so add an `installed`-style guard if a double `start()` would re-init. Verify during integration.)

- [ ] **Step 4: Run the test + build**

Run: `cd brp && swift test --filter VoiceCoordinatorTests` → PASS (4 tests). Then `cd brp && swift build` → clean.

- [ ] **Manual Verification:** covered end-to-end by Task 8.

- [ ] **Step 5: Commit**

```bash
git add brp/Sources/BrotherPaul/Voice/VoiceCoordinator.swift brp/Tests/BrotherPaulTests/VoiceCoordinatorTests.swift
git commit -m "feat(brp): VoiceController assembly + tested wake-engine selection"
```

---

### Task 8: AppDelegate + menu wiring; end-to-end verification

**Type:** Wiring + full manual verification.

**Files:**
- Modify: `brp/Sources/BrotherPaul/AppDelegate.swift` (own a `VoiceController`, start/stop via `applyVoiceConfig()`)
- Modify: `brp/Sources/BrotherPaul/MenuBarController.swift` ("Enable Voice Agent" toggle + status line)
- Modify: `brp/README.md` and `brp/USER_GUIDE.md` (document setup: API key, Porcupine, permissions, confirm tiers)

**Interfaces:**
- Produces: voice agent live in the running app. `AppDelegate` gains `@MainActor private var voice: VoiceController?` and `applyVoiceConfig()` (parallel to `applySnapConfig()`): when `config.voice.enabled`, construct + `start()` the `VoiceController`; otherwise `stop()` and release it. Called from `applicationDidFinishLaunching` and after config reload / menu toggle.

- [ ] **Step 1: Wire AppDelegate**

Add to `AppDelegate`:
```swift
@MainActor private var voice: VoiceController?

func applyVoiceConfig() {
    let cfg = ConfigManager.shared.config.voice
    if cfg.enabled {
        if voice == nil {
            voice = VoiceController(config: cfg)
            voice?.start()
            NSLog("BrotherPaul: voice agent started")
        }
    } else {
        voice?.stop()
        voice = nil
    }
}
```
Call `applyVoiceConfig()` at the end of `applicationDidFinishLaunching`, and from the `onConfigChanged` hook (alongside `applySnapConfig()`).

- [ ] **Step 2: Add the menu toggle + status**

In `MenuBarController`, add an "Enable Voice Agent" checkbox item that flips `config.voice.enabled`, writes config, and calls the `onConfigChanged` hook; plus a disabled status line ("Voice: listening for 'Brother Paul'" / "Voice: push-to-talk ⌃⌥Space" / "Voice: off") reflecting current state.

- [ ] **Step 3: Build the app bundle**

Run: `cd brp && ./build-app.sh && open build/BrotherPaul.app`
Expected: builds and launches; menu shows the new items.

- [ ] **Step 4: Documentation**

Update `README.md` + `USER_GUIDE.md`: enabling voice, `bin/brpaul-anthropic-auth.sh`, the Porcupine access key + `.ppn` setup (and that it's optional — hotkey fallback otherwise), the mic/Speech/Full-Disk permissions, and the three confirm tiers with the deny-list note. Note Porcupine's licensing (free personal tier; commercial needs a paid plan).

- [ ] **Step 5: Full end-to-end Manual Verification**
  1. Fresh config, `voice.enabled = false` → no mic prompt, no panel, zero behavior change. ✓ default-off.
  2. Set the API key (Task 1 helper), enable voice via the menu.
  3. **Hotkey path** (no Porcupine key): ⌃⌥-Space → panel "Listening…" → say "what's my next meeting?" → spoken + panel reply. ✓
  4. **Wake path** (Porcupine key + `.ppn` set, reload config): say "Brother Paul" → listens → "open Slack" → Slack opens, spoken confirmation. ✓
  5. **Safe action** ("snap this window left") runs with no confirmation. ✓ (tiered)
  6. **Risky action** ("close Slack") → Confirm/Deny buttons; Deny → Slack stays open; Confirm → closes. ✓
  7. **Tier `trust`** (`confirmTier: "trust"`): "close Slack" runs without confirm, BUT a destructive `run_system_action` (e.g. a shell `rm`) STILL prompts. ✓ deny-list override (the 2a guarantee, now live).
  8. **No key**: with voice enabled but no API key, a request yields the spoken "I don't have an API key configured yet." ✓
  9. Disable voice via menu → panel/engine torn down; ⌃⌥-Space no longer triggers. ✓

- [ ] **Step 6: Commit**

```bash
git add brp/Sources/BrotherPaul/AppDelegate.swift brp/Sources/BrotherPaul/MenuBarController.swift brp/README.md brp/USER_GUIDE.md
git commit -m "feat(brp): wire voice agent into AppDelegate + menu; docs; voice agent live"
```

---

## Self-Review

**Spec coverage (against `2026-06-18-voice-agent-design.md` §4 + 2a carry-forward):**
- §4 `WakeWordEngine` (Porcupine + hotkey fallback) → Tasks 4–5, selection in Task 7. ✓
- §4 `SpeechTranscribing` (SFSpeechRecognizer, on-device) → Task 3. ✓
- §4 `SpeechSynthesizing` (AVSpeechSynthesizer) → Task 2. ✓
- §4 `VoiceUI` floating panel → Task 6. ✓
- §4 `AppDelegate` wiring + menu items → Task 8. ✓
- §6 config/permissions: `Info.plist` usage strings → Task 3; Keychain key helper → Task 1; menu toggle → Task 8. ✓
- 2a carry-forward #1 (both confirmation seams use `confirmTier`): the `needsConfirmation` gate (Task 7) and the panel `requestConfirmation` blocker (Task 6) — gate uses the tier policy; the panel is the user blocker invoked only when the gate says confirm. End-to-end verified in Task 8 step 7. ✓
- 2a carry-forward #2 (no `assumeIsolated`; wake may fire off-thread): Tasks 4–5 fire `onWake` from handler/audio threads; the controller (2a) hops. Constraint restated. ✓
- 2a carry-forward #3/#4 (`.speaking` dwell / `stop()` tests; cosmetic comments): the real `SystemSpeechSynthesizer` is still fire-and-forget, so `.speaking` remains transient in 2b; revisit only if/when barge-in is added. Noted, not forced. ✓

**Placeholder scan:** none. The single deliberate "verify against the live SDK" note is on Task 5 (Porcupine symbol names) — flagged explicitly because the exact `PorcupineManager` API must be confirmed against Picovoice's current Swift package, not guessed.

**Type consistency:** every concrete type matches its 2a protocol exactly — `SystemSpeechSynthesizer`/`AppleSpeechTranscriber` are `@MainActor` per `SpeechSynthesizing`/`SpeechTranscribing`; `HotkeyWakeEngine`/`PorcupineWakeEngine` are plain classes per `WakeWordEngine` (non-`@MainActor`, may fire off-thread); `VoicePanelWindow` is `@MainActor` per `VoiceUI`. `VoiceController` constructs `VoiceSessionController(wake:transcriber:synthesizer:brain:registry:ui:speakReplies:)` with the exact 2a initializer, and the `ClaudeClient(needsConfirmation:)` closure matches the 2a `(ToolCall) -> Bool` parameter and `ConfirmationPolicy.requiresConfirmation(for:tierString:)` signature.

**Execution note for the human:** Tasks 1, 2, 4, 6, 7 build and (where applicable) unit-test without special hardware and can be done anywhere. Tasks 3, 5, 8 require a real Mac with mic access, and Task 5 additionally needs a Picovoice account (free tier) + a trained "Brother Paul" `.ppn`. Do Task 5's dependency add early if you want to surface any SPM/version issues before building the rest.
