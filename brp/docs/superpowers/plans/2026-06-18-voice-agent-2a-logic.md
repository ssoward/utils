# Voice Agent — Plan 2a: Voice Logic & Seams Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the headless, fully test-driven logic of the voice front-end — the `VoiceSessionController` state machine (mock-tested), the protocol seams the hardware will implement in Plan 2b, and the four Plan-1 carry-forward items (including the tiered-confirmation safety enforcement that is currently inert).

**Architecture:** New `Sources/BrotherPaul/Voice/` subsystem holding protocol seams (`WakeWordEngine`, `SpeechTranscribing`, `SpeechSynthesizing`, `VoiceUI`) plus `VoiceSessionController` — an `@MainActor` state machine that wires wake → listen → think → (confirm) → speak. The agent loop already exists (`ClaudeClient`, Plan 1); this plan makes its confirmation gate **tier-aware** via a new `ConfirmationPolicy` (so the spec's "always-confirm destructive actions" guarantee finally takes effect), surfaces `max_tokens` truncation, adds `AppLauncher.activate(named:)`, and drops the advertised-but-ignored `lookbackHours` tool field. No microphone, audio, Porcupine, or SwiftUI yet — those concrete implementations are Plan 2b, plugging into the seams defined here.

**Tech Stack:** Swift 5.9+, AppKit, Foundation, Swift Package Manager `XCTest`. Builds on the merged Plan-1 Agent core.

## Global Constraints

- Platform: macOS 13+. Swift toolchain Xcode 15+.
- The `VoiceSessionController` and all collaborator protocols touching AppKit are `@MainActor`.
- Confirmation tiers (from `VoiceConfig.confirmTier`, a `String`): `"tiered"` (default), `"confirmEverything"`, `"trust"`. Resolution rule:
  - `confirmEverything` → confirm every tool call.
  - `trust` → confirm only when `ToolRiskClassifier.isDestructive(call)` is true (the always-confirm deny-list overrides trust).
  - `tiered` → confirm when `ToolRiskClassifier.risk(for: call) == .confirm`.
  - Any unrecognized tier string falls back to `tiered` (fail-safe toward more confirmation).
- Do NOT add concrete Porcupine / `SFSpeechRecognizer` / `AVSpeechSynthesizer` / SwiftUI implementations in this plan — only protocols and the controller. Those are Plan 2b.
- Reuse the existing `ToolCall`, `ExecutionOutcome`, `ToolRiskClassifier`, `ClaudeClient`, `AgentToolRegistry` from `Sources/BrotherPaul/Agent/`.
- Tests live in `Tests/BrotherPaulTests/`, named `<Type>Tests.swift`, using `XCTest`. Existing tests must stay green (98 passing at branch start).
- Follow existing style: four-space indent, `NSLog("BrotherPaul: …")` for logging.

---

### Task 1: ConfirmationPolicy (tier-aware confirmation decision)

**Files:**
- Create: `brp/Sources/BrotherPaul/Agent/ConfirmationPolicy.swift`
- Test: `brp/Tests/BrotherPaulTests/ConfirmationPolicyTests.swift`

**Interfaces:**
- Consumes: `ToolCall` (Agent/AgentTypes.swift), `ToolRiskClassifier` (Agent/ToolRiskClassifier.swift).
- Produces: `enum ConfirmTier: String { case tiered, confirmEverything, trust }`; `enum ConfirmationPolicy { static func requiresConfirmation(for call: ToolCall, tier: ConfirmTier) -> Bool; static func requiresConfirmation(for call: ToolCall, tierString: String) -> Bool }`.

- [ ] **Step 1: Write the failing test**

```swift
// brp/Tests/BrotherPaulTests/ConfirmationPolicyTests.swift
import XCTest
@testable import BrotherPaul

final class ConfirmationPolicyTests: XCTestCase {

    private func call(_ name: String, _ input: [String: JSONValue]) -> ToolCall {
        ToolCall(id: "t1", name: name, input: input)
    }
    private var safeCall: ToolCall { call("control_windows", ["zone": .string("leftHalf")]) }
    private var confirmCall: ToolCall { call("control_apps", ["action": .string("close_app"), "app": .string("Slack")]) }
    private var destructiveCall: ToolCall {
        call("run_system_action", ["kind": .string("shell"), "payload": .string("rm -rf ~/x")])
    }

    func testTieredConfirmsOnlyRiskyCalls() {
        XCTAssertFalse(ConfirmationPolicy.requiresConfirmation(for: safeCall, tier: .tiered))
        XCTAssertTrue(ConfirmationPolicy.requiresConfirmation(for: confirmCall, tier: .tiered))
        XCTAssertTrue(ConfirmationPolicy.requiresConfirmation(for: destructiveCall, tier: .tiered))
    }

    func testConfirmEverythingConfirmsEvenSafeCalls() {
        XCTAssertTrue(ConfirmationPolicy.requiresConfirmation(for: safeCall, tier: .confirmEverything))
        XCTAssertTrue(ConfirmationPolicy.requiresConfirmation(for: confirmCall, tier: .confirmEverything))
    }

    func testTrustConfirmsOnlyDestructive() {
        XCTAssertFalse(ConfirmationPolicy.requiresConfirmation(for: safeCall, tier: .trust))
        XCTAssertFalse(ConfirmationPolicy.requiresConfirmation(for: confirmCall, tier: .trust)) // normal "confirm" tool runs in trust mode
        XCTAssertTrue(ConfirmationPolicy.requiresConfirmation(for: destructiveCall, tier: .trust)) // deny-list still overrides
    }

    func testUnknownTierStringFallsBackToTiered() {
        XCTAssertTrue(ConfirmationPolicy.requiresConfirmation(for: confirmCall, tierString: "nonsense"))
        XCTAssertFalse(ConfirmationPolicy.requiresConfirmation(for: safeCall, tierString: "nonsense"))
        // and a valid string resolves
        XCTAssertTrue(ConfirmationPolicy.requiresConfirmation(for: safeCall, tierString: "confirmEverything"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd brp && swift test --filter ConfirmationPolicyTests`
Expected: FAIL to compile — `ConfirmTier` / `ConfirmationPolicy` undefined.

- [ ] **Step 3: Implement**

```swift
// brp/Sources/BrotherPaul/Agent/ConfirmationPolicy.swift
import Foundation

/// Confirmation tier from VoiceConfig.confirmTier.
enum ConfirmTier: String {
    case tiered
    case confirmEverything
    case trust
}

/// Resolves whether a tool call must be confirmed, given the active tier.
/// This is where the spec's "always-confirm destructive actions regardless of
/// tier" guarantee is enforced (the deny-list overrides `trust`).
enum ConfirmationPolicy {

    static func requiresConfirmation(for call: ToolCall, tier: ConfirmTier) -> Bool {
        switch tier {
        case .confirmEverything:
            return true
        case .trust:
            return ToolRiskClassifier.isDestructive(call)
        case .tiered:
            return ToolRiskClassifier.risk(for: call) == .confirm
        }
    }

    /// String overload — unrecognized tier strings fall back to `.tiered` (fail-safe).
    static func requiresConfirmation(for call: ToolCall, tierString: String) -> Bool {
        requiresConfirmation(for: call, tier: ConfirmTier(rawValue: tierString) ?? .tiered)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd brp && swift test --filter ConfirmationPolicyTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add brp/Sources/BrotherPaul/Agent/ConfirmationPolicy.swift brp/Tests/BrotherPaulTests/ConfirmationPolicyTests.swift
git commit -m "feat(brp): add ConfirmationPolicy for tier-aware confirmation (enforces deny-list in trust mode)"
```

---

### Task 2: Make ClaudeClient's confirmation gate injectable

**Files:**
- Modify: `brp/Sources/BrotherPaul/Agent/ClaudeClient.swift`
- Test: `brp/Tests/BrotherPaulTests/ClaudeClientTests.swift` (add cases; keep existing)

**Interfaces:**
- Consumes: `ConfirmationPolicy` (Task 1), `ToolCall`, `ToolRiskClassifier`.
- Produces: `ClaudeClient.init` gains a trailing parameter `needsConfirmation: @escaping (ToolCall) -> Bool = { ToolRiskClassifier.risk(for: $0) == .confirm }`. The loop's confirmation gate calls `needsConfirmation(call)` instead of `ToolRiskClassifier.risk(for: call) == .confirm` directly. Default preserves Plan-1 behavior so existing tests and callers are unaffected.

- [ ] **Step 1: Write the failing test**

Add these two methods to the existing `ClaudeClientTests` class in `brp/Tests/BrotherPaulTests/ClaudeClientTests.swift` (keep all existing tests; reuse the existing `StubTransport` and `makeClient` helpers — but these tests build their own client to inject the policy):

```swift
    func testInjectedPolicyCanConfirmASafeTool() async throws {
        // confirmEverything-style: even a safe tool must be confirmed.
        let transport = StubTransport([
            MessagesResponse(content: [
                .toolUse(id: "tu1", name: "control_windows", input: ["zone": .string("leftHalf")])
            ], stop_reason: "tool_use"),
            MessagesResponse(content: [.text("Done.")], stop_reason: "end_turn")
        ])
        let secrets = InMemorySecretStore()
        secrets.set("sk-ant-test", for: SecretKey.anthropicAPIKey)
        let client = ClaudeClient(config: .default, tools: [], systemPrompt: "s",
                                  secrets: secrets, transport: transport,
                                  needsConfirmation: { _ in true })   // confirm everything
        var confirmed = false
        var executed = false
        _ = try await client.send("snap left",
            confirm: { _ in confirmed = true; return false },        // deny
            execute: { _ in executed = true; return .ok("") })
        XCTAssertTrue(confirmed)        // safe tool WAS sent to confirm
        XCTAssertFalse(executed)        // denied → not executed
    }

    func testInjectedPolicyCanSkipConfirmationEntirely() async throws {
        // trust-style: even a normally-risky tool runs without confirmation.
        let transport = StubTransport([
            MessagesResponse(content: [
                .toolUse(id: "tu1", name: "control_apps",
                         input: ["action": .string("close_app"), "app": .string("Slack")])
            ], stop_reason: "tool_use"),
            MessagesResponse(content: [.text("Closed.")], stop_reason: "end_turn")
        ])
        let secrets = InMemorySecretStore()
        secrets.set("sk-ant-test", for: SecretKey.anthropicAPIKey)
        let client = ClaudeClient(config: .default, tools: [], systemPrompt: "s",
                                  secrets: secrets, transport: transport,
                                  needsConfirmation: { _ in false })  // never confirm
        var confirmed = false
        var executed = false
        let reply = try await client.send("close slack",
            confirm: { _ in confirmed = true; return true },
            execute: { _ in executed = true; return .ok("closed") })
        XCTAssertFalse(confirmed)       // confirm never called
        XCTAssertTrue(executed)         // ran directly
        XCTAssertEqual(reply, "Closed.")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd brp && swift test --filter ClaudeClientTests`
Expected: FAIL to compile — `ClaudeClient.init` has no `needsConfirmation:` parameter.

- [ ] **Step 3: Modify ClaudeClient**

In `brp/Sources/BrotherPaul/Agent/ClaudeClient.swift`:

- Add a stored property near the other `private let`s:
  ```swift
  private let needsConfirmation: (ToolCall) -> Bool
  ```
- Add the parameter to `init` (as the last parameter, with a default that preserves Plan-1 behavior) and assign it:
  ```swift
  init(config: VoiceConfig, tools: [APIToolDefinition], systemPrompt: String,
       secrets: SecretStore, transport: MessagesTransport,
       needsConfirmation: @escaping (ToolCall) -> Bool = { ToolRiskClassifier.risk(for: $0) == .confirm }) {
      self.config = config
      self.tools = tools
      self.systemPrompt = systemPrompt
      self.secrets = secrets
      self.transport = transport
      self.needsConfirmation = needsConfirmation
  }
  ```
- In the tool loop, replace the gate line:
  ```swift
  if ToolRiskClassifier.risk(for: call) == .confirm {
  ```
  with:
  ```swift
  if needsConfirmation(call) {
  ```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd brp && swift test --filter ClaudeClientTests`
Expected: PASS (8 tests — the 6 existing + 2 new). The existing `testRiskyToolAsksConfirmationAndSkipsWhenDenied` still passes via the default `needsConfirmation`.

- [ ] **Step 5: Commit**

```bash
git add brp/Sources/BrotherPaul/Agent/ClaudeClient.swift brp/Tests/BrotherPaulTests/ClaudeClientTests.swift
git commit -m "feat(brp): make ClaudeClient confirmation gate injectable (default unchanged)"
```

---

### Task 3: Surface max_tokens truncation in ClaudeClient

**Files:**
- Modify: `brp/Sources/BrotherPaul/Agent/ClaudeClient.swift`
- Test: `brp/Tests/BrotherPaulTests/ClaudeClientTests.swift` (add a case)

**Interfaces:**
- Produces: when the loop returns the final text and `response.stop_reason == "max_tokens"`, the returned string is annotated so the truncation isn't silent.

- [ ] **Step 1: Write the failing test**

Add to `ClaudeClientTests`:

```swift
    func testMaxTokensReplyIsMarkedTruncated() async throws {
        let transport = StubTransport([
            MessagesResponse(content: [.text("Here is the first part")], stop_reason: "max_tokens")
        ])
        let client = makeClient(transport)
        let reply = try await client.send("tell me a long story",
            confirm: { _ in true }, execute: { _ in .ok("") })
        XCTAssertTrue(reply.contains("Here is the first part"))
        XCTAssertTrue(reply.lowercased().contains("cut off"))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd brp && swift test --filter ClaudeClientTests`
Expected: FAIL — reply equals "Here is the first part" with no "cut off" marker.

- [ ] **Step 3: Modify ClaudeClient**

In the loop, the early-return for no tool calls is currently:
```swift
if toolCalls.isEmpty {
    return firstText(response.content) ?? ""
}
```
Replace it with:
```swift
if toolCalls.isEmpty {
    let text = firstText(response.content) ?? ""
    if response.stop_reason == "max_tokens" {
        return text.isEmpty
            ? "My reply was cut off before I could finish."
            : text + " … (my reply was cut off)."
    }
    return text
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd brp && swift test --filter ClaudeClientTests`
Expected: PASS (9 tests). Existing `testToolUseWithEndTurnStillExecutes` and others unaffected (they don't use `max_tokens`).

- [ ] **Step 5: Commit**

```bash
git add brp/Sources/BrotherPaul/Agent/ClaudeClient.swift brp/Tests/BrotherPaulTests/ClaudeClientTests.swift
git commit -m "feat(brp): mark max_tokens-truncated replies instead of returning them silently"
```

---

### Task 4: AppLauncher.activate(named:) + use it for window focus

**Files:**
- Modify: `brp/Sources/BrotherPaul/AppLauncher.swift`
- Modify: `brp/Sources/BrotherPaul/Agent/WindowControlExecutor.swift`
- Test: `brp/Tests/BrotherPaulTests/AppLauncherSurfaceTests.swift` (add a case)

**Interfaces:**
- Produces: `@discardableResult static func activate(named name: String) -> Bool` on `AppLauncher` — brings an already-running app to the front (does NOT launch it); returns true iff a running match was activated. `WindowControlExecutor` focuses a named app by trying `activate` first and only falling back to `launchApp` if it isn't running.

- [ ] **Step 1: Write the failing test**

Add to `AppLauncherSurfaceTests`:

```swift
    func testActivateUnknownAppReturnsFalse() {
        XCTAssertFalse(AppLauncher.activate(named: "NoSuchApp_ZZZ_12345"))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd brp && swift test --filter AppLauncherSurfaceTests`
Expected: FAIL to compile — `activate(named:)` undefined.

- [ ] **Step 3: Add `activate(named:)` to AppLauncher**

In `brp/Sources/BrotherPaul/AppLauncher.swift`, add:

```swift
/// Bring an already-running app to the front WITHOUT launching it.
/// Returns true iff a running match (by bundle id or localized name) was activated.
@discardableResult
static func activate(named name: String) -> Bool {
    let myBundle = Bundle.main.bundleIdentifier
    let match = NSWorkspace.shared.runningApplications.first { app in
        if app.bundleIdentifier == myBundle { return false }
        if let bid = app.bundleIdentifier, bid.caseInsensitiveCompare(name) == .orderedSame { return true }
        if let n = app.localizedName, n.caseInsensitiveCompare(name) == .orderedSame { return true }
        return false
    }
    guard let app = match else { return false }
    return app.activate(options: [])
}
```

- [ ] **Step 4: Use it in WindowControlExecutor**

In `brp/Sources/BrotherPaul/Agent/WindowControlExecutor.swift`, the optional app-focus block currently launches the app:
```swift
if let app = call.input["app"]?.stringValue {
    AppLauncher.launchApp(named: app)
    try? await Task.sleep(nanoseconds: 400_000_000)
}
```
Replace the body so it prefers activating a running app and only launches if it isn't running:
```swift
if let app = call.input["app"]?.stringValue {
    if !AppLauncher.activate(named: app) {
        AppLauncher.launchApp(named: app)
    }
    try? await Task.sleep(nanoseconds: 400_000_000)
}
```

- [ ] **Step 5: Run tests**

Run: `cd brp && swift test --filter AppLauncherSurfaceTests`
Expected: PASS (3 tests). Then `cd brp && swift test --filter AppControlExecutorTests` — still PASS (4 tests; the unknown-zone test path is unchanged).

- [ ] **Step 6: Commit**

```bash
git add brp/Sources/BrotherPaul/AppLauncher.swift brp/Sources/BrotherPaul/Agent/WindowControlExecutor.swift brp/Tests/BrotherPaulTests/AppLauncherSurfaceTests.swift
git commit -m "feat(brp): add AppLauncher.activate(named:); WindowControlExecutor focuses without relaunching"
```

---

### Task 5: Drop the ignored lookbackHours field from query_schedule

**Files:**
- Modify: `brp/Sources/BrotherPaul/Agent/AgentTools.swift`
- Test: `brp/Tests/BrotherPaulTests/AgentToolsTests.swift` (add a case)

**Interfaces:**
- Produces: the `query_schedule` tool schema no longer advertises `lookbackHours` (the executor never read it, so the schema was lying to the model). `sources` remains.

- [ ] **Step 1: Write the failing test**

Add to `AgentToolsTests`:

```swift
    func testQueryScheduleSchemaHasSourcesButNotLookbackHours() {
        let tool = AgentTools.definitions().first { $0.name == "query_schedule" }!
        guard case .object(let schema) = tool.input_schema,
              case .object(let props)? = schema["properties"] else {
            return XCTFail("query_schedule schema malformed")
        }
        XCTAssertNotNil(props["sources"])
        XCTAssertNil(props["lookbackHours"], "lookbackHours was advertised but never honored — it must be removed")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd brp && swift test --filter AgentToolsTests`
Expected: FAIL — `props["lookbackHours"]` is currently present.

- [ ] **Step 3: Remove the field**

In `brp/Sources/BrotherPaul/Agent/AgentTools.swift`, in the `query_schedule` tool definition, delete the `"lookbackHours"` entry from its `properties` object (keep `"sources"`). The `query_schedule` properties should contain only `sources` after this change.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd brp && swift test --filter AgentToolsTests`
Expected: PASS (5 tests — the 4 existing + 1 new).

- [ ] **Step 5: Commit**

```bash
git add brp/Sources/BrotherPaul/Agent/AgentTools.swift brp/Tests/BrotherPaulTests/AgentToolsTests.swift
git commit -m "fix(brp): drop unimplemented lookbackHours from query_schedule tool schema"
```

---

### Task 6: Voice protocol seams + brain/registry conformances

**Files:**
- Create: `brp/Sources/BrotherPaul/Voice/VoiceSeams.swift`
- Test: `brp/Tests/BrotherPaulTests/VoiceSeamsTests.swift`

**Interfaces:**
- Consumes: `ToolCall`, `ExecutionOutcome` (Agent/AgentTypes.swift), `ClaudeClient` (Agent/ClaudeClient.swift), `AgentToolRegistry` (Agent/AgentTools.swift).
- Produces (the seams Plan 2b implements with real hardware/UI):
  - `protocol WakeWordEngine: AnyObject { var onWake: (() -> Void)? { get set }; func start(); func stop() }`
  - `@MainActor protocol SpeechTranscribing: AnyObject { func startListening(onFinal: @escaping (String) -> Void); func stop() }`
  - `@MainActor protocol SpeechSynthesizing: AnyObject { func speak(_ text: String); func stop() }`
  - `@MainActor protocol ToolDispatching: AnyObject { func dispatch(_ call: ToolCall) async -> ExecutionOutcome }`
  - `protocol AgentBrain: AnyObject { func send(_ transcript: String, confirm: @escaping (ToolCall) async -> Bool, execute: @escaping (ToolCall) async -> ExecutionOutcome) async throws -> String }`
  - `enum VoiceUIState: Equatable { case idle, listening, thinking(String), confirming(ToolCall), replied(String), error(String) }`
  - `@MainActor protocol VoiceUI: AnyObject { func show(_ state: VoiceUIState); func requestConfirmation(_ call: ToolCall) async -> Bool }`
  - Conformances: `extension ClaudeClient: AgentBrain {}` and `extension AgentToolRegistry: ToolDispatching {}` (both already have the matching method signatures from Plan 1).

- [ ] **Step 1: Write the failing test**

```swift
// brp/Tests/BrotherPaulTests/VoiceSeamsTests.swift
import XCTest
@testable import BrotherPaul

final class VoiceSeamsTests: XCTestCase {

    @MainActor
    func testAgentToolRegistryConformsToToolDispatching() async {
        let dispatcher: ToolDispatching = AgentToolRegistry(allowSystemControl: true)
        // Unknown tool → failure, proving the protocol call routes into the registry.
        let outcome = await dispatcher.dispatch(ToolCall(id: "1", name: "nope", input: [:]))
        XCTAssertTrue(outcome.isError)
    }

    func testClaudeClientConformsToAgentBrain() {
        let secrets = InMemorySecretStore()
        let brain: AgentBrain = ClaudeClient(config: .default, tools: [], systemPrompt: "s",
                                             secrets: secrets, transport: NoopTransport())
        XCTAssertNotNil(brain)   // compile-time proof of conformance
    }

    func testVoiceUIStateEquatable() {
        XCTAssertEqual(VoiceUIState.thinking("hi"), .thinking("hi"))
        XCTAssertNotEqual(VoiceUIState.replied("a"), .replied("b"))
        XCTAssertEqual(VoiceUIState.idle, .idle)
    }
}

private final class NoopTransport: MessagesTransport {
    func send(_ request: MessagesRequest) async throws -> MessagesResponse {
        MessagesResponse(content: [], stop_reason: "end_turn")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd brp && swift test --filter VoiceSeamsTests`
Expected: FAIL to compile — the protocols and conformances don't exist.

- [ ] **Step 3: Implement the seams**

```swift
// brp/Sources/BrotherPaul/Voice/VoiceSeams.swift
import Foundation

/// Continuously listens for the wake word and fires `onWake`. Implemented by
/// Porcupine (or the hotkey fallback) in Plan 2b.
protocol WakeWordEngine: AnyObject {
    var onWake: (() -> Void)? { get set }
    func start()
    func stop()
}

/// Captures the user's spoken request and reports the final transcript.
/// Implemented by SFSpeechRecognizer in Plan 2b.
@MainActor
protocol SpeechTranscribing: AnyObject {
    func startListening(onFinal: @escaping (String) -> Void)
    func stop()
}

/// Speaks replies aloud. Implemented by AVSpeechSynthesizer in Plan 2b.
@MainActor
protocol SpeechSynthesizing: AnyObject {
    func speak(_ text: String)
    func stop()
}

/// Executes a tool call. AgentToolRegistry conforms.
@MainActor
protocol ToolDispatching: AnyObject {
    func dispatch(_ call: ToolCall) async -> ExecutionOutcome
}

/// The conversational brain. ClaudeClient conforms.
protocol AgentBrain: AnyObject {
    func send(_ transcript: String,
              confirm: @escaping (ToolCall) async -> Bool,
              execute: @escaping (ToolCall) async -> ExecutionOutcome) async throws -> String
}

/// What the floating panel renders. Implemented by the SwiftUI panel in Plan 2b.
enum VoiceUIState: Equatable {
    case idle
    case listening
    case thinking(String)        // the heard transcript
    case confirming(ToolCall)    // a risky action awaiting yes/no
    case replied(String)         // the spoken reply, shown as text
    case error(String)
}

@MainActor
protocol VoiceUI: AnyObject {
    func show(_ state: VoiceUIState)
    /// Ask the user to approve a risky action (spoken "yes"/"no" or a panel button).
    func requestConfirmation(_ call: ToolCall) async -> Bool
}

extension ClaudeClient: AgentBrain {}
extension AgentToolRegistry: ToolDispatching {}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd brp && swift test --filter VoiceSeamsTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add brp/Sources/BrotherPaul/Voice/VoiceSeams.swift brp/Tests/BrotherPaulTests/VoiceSeamsTests.swift
git commit -m "feat(brp): add voice protocol seams + AgentBrain/ToolDispatching conformances"
```

---

### Task 7: VoiceSessionController state machine

**Files:**
- Create: `brp/Sources/BrotherPaul/Voice/VoiceSessionController.swift`
- Test: `brp/Tests/BrotherPaulTests/VoiceSessionControllerTests.swift`

**Interfaces:**
- Consumes: all seams from Task 6 (`WakeWordEngine`, `SpeechTranscribing`, `SpeechSynthesizing`, `ToolDispatching`, `AgentBrain`, `VoiceUI`, `VoiceUIState`), `ToolCall`, `ExecutionOutcome`, `ClaudeClientError`.
- Produces: `@MainActor final class VoiceSessionController` with `init(wake:transcriber:synthesizer:brain:registry:ui:speakReplies:)`, a `private(set) var state: State`, `enum State { case idle, listening, thinking, confirming, speaking }`, a `func start()` (installs the wake callback + starts the engine), and an `func handleFinalTranscript(_ text: String) async` that runs one full turn. The wake callback calls an internal `beginListening()`.

- [ ] **Step 1: Write the failing test**

```swift
// brp/Tests/BrotherPaulTests/VoiceSessionControllerTests.swift
import XCTest
@testable import BrotherPaul

@MainActor
final class VoiceSessionControllerTests: XCTestCase {

    // MARK: - Mocks

    final class MockWake: WakeWordEngine {
        var onWake: (() -> Void)?
        private(set) var started = false
        func start() { started = true }
        func stop() {}
        func fire() { onWake?() }
    }

    final class MockSTT: SpeechTranscribing {
        private(set) var startCount = 0
        private(set) var stopped = false
        var onFinal: ((String) -> Void)?
        func startListening(onFinal: @escaping (String) -> Void) { startCount += 1; self.onFinal = onFinal }
        func stop() { stopped = true }
    }

    final class MockTTS: SpeechSynthesizing {
        private(set) var spoken: [String] = []
        func speak(_ text: String) { spoken.append(text) }
        func stop() {}
    }

    final class MockRegistry: ToolDispatching {
        private(set) var dispatched: [String] = []
        func dispatch(_ call: ToolCall) async -> ExecutionOutcome { dispatched.append(call.name); return .ok("did \(call.name)") }
    }

    final class MockUI: VoiceUI {
        private(set) var states: [VoiceUIState] = []
        var confirmResult = true
        private(set) var confirmAsks = 0
        func show(_ state: VoiceUIState) { states.append(state) }
        func requestConfirmation(_ call: ToolCall) async -> Bool { confirmAsks += 1; return confirmResult }
    }

    /// A brain that returns a canned reply, optionally exercising confirm/execute
    /// with a scripted tool call first (simulating ClaudeClient's loop).
    final class MockBrain: AgentBrain {
        var reply = "All set."
        var scriptedCall: ToolCall?
        var errorToThrow: Error?
        func send(_ transcript: String,
                  confirm: @escaping (ToolCall) async -> Bool,
                  execute: @escaping (ToolCall) async -> ExecutionOutcome) async throws -> String {
            if let e = errorToThrow { throw e }
            if let call = scriptedCall {
                if await confirm(call) { _ = await execute(call) }
            }
            return reply
        }
    }

    private func makeController(
        wake: MockWake = MockWake(), stt: MockSTT = MockSTT(), tts: MockTTS = MockTTS(),
        brain: MockBrain = MockBrain(), registry: MockRegistry = MockRegistry(),
        ui: MockUI = MockUI(), speakReplies: Bool = true
    ) -> (VoiceSessionController, MockWake, MockSTT, MockTTS, MockBrain, MockRegistry, MockUI) {
        let c = VoiceSessionController(wake: wake, transcriber: stt, synthesizer: tts,
                                       brain: brain, registry: registry, ui: ui, speakReplies: speakReplies)
        return (c, wake, stt, tts, brain, registry, ui)
    }

    // MARK: - Tests

    func testWakeBeginsListening() {
        let (c, wake, stt, _, _, _, ui) = makeController()
        c.start()
        XCTAssertTrue(wake.started)
        wake.fire()
        XCTAssertEqual(c.state, .listening)
        XCTAssertEqual(stt.startCount, 1)
        XCTAssertEqual(ui.states.last, .listening)
    }

    func testEmptyTranscriptRepromptsAndReturnsToIdle() async {
        let (c, _, stt, tts, _, _, _) = makeController()
        c.start()
        await c.handleFinalTranscript("   ")
        XCTAssertTrue(stt.stopped)
        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(tts.spoken.count, 1)
        XCTAssertTrue(tts.spoken[0].lowercased().contains("didn't catch"))
    }

    func testSimpleReplyIsSpokenAndShown() async {
        let brain = MockBrain(); brain.reply = "Your next meeting is at 2."
        let (c, _, _, tts, _, _, ui) = makeController(brain: brain)
        await c.handleFinalTranscript("what's next?")
        XCTAssertEqual(tts.spoken, ["Your next meeting is at 2."])
        XCTAssertEqual(ui.states.last, .idle)
        XCTAssertTrue(ui.states.contains(.replied("Your next meeting is at 2.")))
        XCTAssertEqual(c.state, .idle)
    }

    func testApprovedConfirmationExecutesTool() async {
        let brain = MockBrain()
        brain.scriptedCall = ToolCall(id: "1", name: "control_apps",
                                      input: ["action": .string("close_app"), "app": .string("Slack")])
        let ui = MockUI(); ui.confirmResult = true
        let registry = MockRegistry()
        let (c, _, _, _, _, _, _) = makeController(brain: brain, registry: registry, ui: ui)
        await c.handleFinalTranscript("close slack")
        XCTAssertEqual(ui.confirmAsks, 1)
        XCTAssertEqual(registry.dispatched, ["control_apps"])
    }

    func testDeniedConfirmationSkipsExecution() async {
        let brain = MockBrain()
        brain.scriptedCall = ToolCall(id: "1", name: "control_apps",
                                      input: ["action": .string("close_app"), "app": .string("Slack")])
        let ui = MockUI(); ui.confirmResult = false
        let registry = MockRegistry()
        let (c, _, _, _, _, _, _) = makeController(brain: brain, registry: registry, ui: ui)
        await c.handleFinalTranscript("close slack")
        XCTAssertEqual(ui.confirmAsks, 1)
        XCTAssertTrue(registry.dispatched.isEmpty)
    }

    func testBrainErrorIsSpokenAndReturnsToIdle() async {
        let brain = MockBrain(); brain.errorToThrow = ClaudeClientError.missingAPIKey
        let (c, _, _, tts, _, _, ui) = makeController(brain: brain)
        await c.handleFinalTranscript("hello")
        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(tts.spoken.count, 1)
        if case .error = ui.states.last {} else { XCTFail("expected error state") }
    }

    func testSpeakRepliesFalseStaysSilent() async {
        let brain = MockBrain(); brain.reply = "Done."
        let (c, _, _, tts, _, _, _) = makeController(brain: brain, speakReplies: false)
        await c.handleFinalTranscript("do it")
        XCTAssertTrue(tts.spoken.isEmpty)
        XCTAssertEqual(c.state, .idle)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd brp && swift test --filter VoiceSessionControllerTests`
Expected: FAIL to compile — `VoiceSessionController` undefined.

- [ ] **Step 3: Implement VoiceSessionController**

```swift
// brp/Sources/BrotherPaul/Voice/VoiceSessionController.swift
import Foundation

/// Orchestrates one voice interaction: wake → listen → think → (confirm) → speak.
/// The single stateful coordinator; all collaborators are injected protocols so
/// the state machine is fully unit-testable without hardware.
@MainActor
final class VoiceSessionController {

    enum State: Equatable { case idle, listening, thinking, confirming, speaking }

    private(set) var state: State = .idle

    private let wake: WakeWordEngine
    private let transcriber: SpeechTranscribing
    private let synthesizer: SpeechSynthesizing
    private let brain: AgentBrain
    private let registry: ToolDispatching
    private let ui: VoiceUI
    private let speakReplies: Bool

    init(wake: WakeWordEngine, transcriber: SpeechTranscribing, synthesizer: SpeechSynthesizing,
         brain: AgentBrain, registry: ToolDispatching, ui: VoiceUI, speakReplies: Bool) {
        self.wake = wake
        self.transcriber = transcriber
        self.synthesizer = synthesizer
        self.brain = brain
        self.registry = registry
        self.ui = ui
        self.speakReplies = speakReplies
    }

    /// Install the wake callback and start the engine.
    func start() {
        wake.onWake = { [weak self] in
            Task { @MainActor in self?.beginListening() }
        }
        wake.start()
    }

    func stop() {
        wake.stop()
        transcriber.stop()
        synthesizer.stop()
        state = .idle
    }

    /// Wake fired — start capturing the request (ignored unless idle).
    func beginListening() {
        guard state == .idle else { return }
        state = .listening
        ui.show(.listening)
        transcriber.startListening { [weak self] text in
            Task { @MainActor in await self?.handleFinalTranscript(text) }
        }
    }

    /// Run one full turn for a final transcript.
    func handleFinalTranscript(_ text: String) async {
        transcriber.stop()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            finish(error: "Sorry, I didn't catch that.")
            return
        }

        state = .thinking
        ui.show(.thinking(trimmed))

        do {
            let reply = try await brain.send(
                trimmed,
                confirm: { [weak self] call in
                    guard let self else { return false }
                    self.state = .confirming
                    self.ui.show(.confirming(call))
                    return await self.ui.requestConfirmation(call)
                },
                execute: { [weak self] call in
                    guard let self else { return .failure("Session ended.") }
                    return await self.registry.dispatch(call)
                })
            speakAndFinish(reply)
        } catch {
            finish(error: Self.message(for: error))
        }
    }

    // MARK: - Helpers

    private func speakAndFinish(_ reply: String) {
        state = .speaking
        ui.show(.replied(reply))
        if speakReplies, !reply.isEmpty { synthesizer.speak(reply) }
        state = .idle
        ui.show(.idle)
    }

    private func finish(error message: String) {
        if speakReplies { synthesizer.speak(message) }
        ui.show(.error(message))
        state = .idle
    }

    static func message(for error: Error) -> String {
        switch error {
        case ClaudeClientError.missingAPIKey:
            return "I don't have an API key configured yet."
        case ClaudeClientError.refused:
            return "Sorry, I can't help with that."
        case ClaudeClientError.httpError:
            return "I couldn't reach the service just now."
        default:
            return "Something went wrong handling that."
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd brp && swift test --filter VoiceSessionControllerTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add brp/Sources/BrotherPaul/Voice/VoiceSessionController.swift brp/Tests/BrotherPaulTests/VoiceSessionControllerTests.swift
git commit -m "feat(brp): add VoiceSessionController state machine (mock-tested)"
```

---

### Task 8: Full-suite green + Plan-2b seam

**Files:**
- Test: whole suite.

**Interfaces:**
- Produces: a verified, fully green voice-logic layer. Plan 2b implements `WakeWordEngine` (Porcupine + hotkey), `SpeechTranscribing` (SFSpeechRecognizer), `SpeechSynthesizing` (AVSpeechSynthesizer), and `VoiceUI` (SwiftUI floating panel), then constructs `VoiceSessionController` in `AppDelegate` with a `ClaudeClient` whose `needsConfirmation` is `{ ConfirmationPolicy.requiresConfirmation(for: $0, tierString: config.voice.confirmTier) }`, and wires the Keychain key + Info.plist usage strings + menu items.

- [ ] **Step 1: Run the entire test suite**

Run: `cd brp && swift test`
Expected: PASS — all prior tests plus `ConfirmationPolicyTests`, the new `ClaudeClientTests` cases, `VoiceSeamsTests`, and `VoiceSessionControllerTests`.

- [ ] **Step 2: Build the app target**

Run: `cd brp && swift build`
Expected: builds cleanly (the Voice layer is unused by the running app until Plan 2b wires it in — expected).

- [ ] **Step 3: Commit (only if a test-script change was needed)**

```bash
git add -A
git commit -m "test(brp): verify voice-logic layer (Plan 2a) suite is green"
```

---

## Self-Review

**Spec coverage (against `2026-06-18-voice-agent-design.md` §4 components + Plan-1 carry-forward):**
- §4 `VoiceSessionController` (the stateful orchestrator) → Task 7. ✓
- §4 protocol seams (`WakeWordEngine`, `SpeechTranscribing`, `SpeechSynthesizing`) + `VoiceUI` presenter → Task 6. ✓
- §7 tiered safety **enforcement** (the deny-list overriding `trust`) → Tasks 1–2 (`ConfirmationPolicy` + injectable gate). ✓
- Carry-forward: confirmTier resolution → Tasks 1–2; `max_tokens` truncation → Task 3; `AppLauncher.activate(named:)` → Task 4; `lookbackHours` honesty → Task 5. ✓
- **Deferred to Plan 2b** (hardware/UI/dependency, manual-verified): Porcupine `WakeWordEngine` + hotkey fallback, `SFSpeechRecognizer` transcriber, `AVSpeechSynthesizer` synthesizer, SwiftUI `VoicePanelWindow`/`View` implementing `VoiceUI`, `AppDelegate`/`MenuBarController` wiring, `Info.plist` usage strings, Keychain auth helper. These implement the seams from Task 6 and construct the controller per Task 8's interface note.

**Placeholder scan:** none — every code step is complete.

**Type consistency:** `ConfirmTier`/`ConfirmationPolicy` (Task 1) are used by Task 2's injected gate and by Plan 2b's controller construction (Task 8 note). `needsConfirmation: (ToolCall) -> Bool` (Task 2) matches the loop call site. The Task 6 seam signatures (`AgentBrain.send`, `ToolDispatching.dispatch`, `VoiceUI.show`/`requestConfirmation`, `VoiceUIState` cases) are exactly what `VoiceSessionController` (Task 7) consumes and what the Task 7 mocks implement. `AppLauncher.activate(named:) -> Bool` (Task 4) matches the `WindowControlExecutor` call site.
