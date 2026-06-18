# Voice Agent — Plan 1: Agent Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the headless, test-driven "brain" of the Brother Paul voice agent — a Claude-backed tool-use loop that can open/close apps, snap windows, query the schedule, and run gated system actions — with no microphone or UI yet.

**Architecture:** A new `Sources/BrotherPaul/Agent/` subsystem. `ClaudeClient` talks to the Anthropic Messages API over `URLSession` (raw HTTPS, since Swift has no official SDK) and runs a **manual** client-side tool-use loop. Claude returns `tool_use` blocks; the loop classifies each by risk, optionally asks for confirmation (via an injected closure — wired to voice/UI in Plan 2), executes it against the existing app pillars, and returns `tool_result` until `stop_reason == "end_turn"`. The Anthropic key lives in Keychain behind a `SecretStore` protocol so tests use an in-memory store.

**Tech Stack:** Swift 5.9+, AppKit, Foundation `URLSession`, `Security` (Keychain), Swift Package Manager `XCTest`. Anthropic Messages API (`POST /v1/messages`), model `claude-opus-4-8`.

## Global Constraints

- Platform: macOS 13+ (matches existing app). Swift toolchain Xcode 15+.
- API endpoint: `https://api.anthropic.com/v1/messages`. Required headers: `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`.
- Model default: `claude-opus-4-8` (configurable). Thinking: `{"type":"adaptive","display":"omitted"}`. `output_config.effort` from config (`"medium"` default).
- The Anthropic API key is **never** stored in `config.json` — only in Keychain (or the in-memory test store).
- Config decoding MUST preserve backward compatibility: missing `voice` block decodes to defaults (use the existing `decodeIfPresent ?? default` pattern from `MissionControlConfig`).
- Follow existing code style: `enum` namespaces for stateless helpers, `NSLog("BrotherPaul: …")` for logging, four-space indentation.
- Tests live in `Tests/BrotherPaulTests/`, named `<Type>Tests.swift`, using `XCTest`.
- Tool names (exact, lowercase): `control_apps`, `control_windows`, `query_schedule`, `run_system_action`.

---

### Task 1: VoiceConfig model + AppConfig wiring

**Files:**
- Modify: `brp/Sources/BrotherPaul/Models.swift`
- Test: `brp/Tests/BrotherPaulTests/VoiceConfigTests.swift`

**Interfaces:**
- Produces: `struct VoiceConfig: Codable, Equatable` with fields below and `static let default`; `struct VoiceWakeWordConfig: Codable, Equatable`; `AppConfig.voice: VoiceConfig` (decoded with `decodeIfPresent ?? .default`).

- [ ] **Step 1: Write the failing test**

```swift
// brp/Tests/BrotherPaulTests/VoiceConfigTests.swift
import XCTest
@testable import BrotherPaul

final class VoiceConfigTests: XCTestCase {

    func testDefaultsAreSafe() {
        let v = VoiceConfig.default
        XCTAssertFalse(v.enabled)                 // master switch OFF by default
        XCTAssertEqual(v.model, "claude-opus-4-8")
        XCTAssertEqual(v.effort, "medium")
        XCTAssertEqual(v.maxTokens, 1024)
        XCTAssertTrue(v.speakReplies)
        XCTAssertTrue(v.allowSystemControl)
        XCTAssertEqual(v.confirmTier, "tiered")
        XCTAssertTrue(v.wakeWord.enabled)
        XCTAssertTrue(v.pushToTalkFallback)
    }

    func testOlderConfigWithoutVoiceBlockDecodesToDefault() throws {
        // A config.json from before this feature existed.
        let json = """
        { "hideOthersAfterLaunch": true, "defaultMode": "Full", "modes": [] }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(config.voice, VoiceConfig.default)
    }

    func testVoiceBlockRoundTrips() throws {
        var v = VoiceConfig.default
        v.enabled = true
        v.model = "claude-haiku-4-5"
        let config = AppConfig(hideOthersAfterLaunch: true, defaultMode: "Full", modes: [], voice: v)
        let data = try JSONEncoder().encode(config)
        let back = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(back.voice, v)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd brp && swift test --filter VoiceConfigTests`
Expected: FAIL to compile — `VoiceConfig` undefined, `AppConfig` has no `voice` parameter.

- [ ] **Step 3: Add the models**

Add to `brp/Sources/BrotherPaul/Models.swift` (after `GraphConfig`):

```swift
struct VoiceWakeWordConfig: Codable, Equatable {
    /// Listen for the "Brother Paul" wake word continuously.
    var enabled: Bool = true
    /// Picovoice access key (free tier covers personal use). Empty → wake word disabled, hotkey fallback used.
    var porcupineAccessKey: String = ""
    /// Path to the trained "Brother Paul" .ppn keyword file.
    var keywordPath: String = ""

    static let `default` = VoiceWakeWordConfig()
}

struct VoiceConfig: Codable, Equatable {
    /// Master switch for the whole voice agent. OFF by default.
    var enabled: Bool
    /// Claude model id. Configurable; Haiku/Sonnet lower latency.
    var model: String
    /// output_config.effort: low | medium | high | max.
    var effort: String
    /// Per-turn output cap.
    var maxTokens: Int
    var wakeWord: VoiceWakeWordConfig
    /// Use a push-to-talk hotkey when no Porcupine key is configured.
    var pushToTalkFallback: Bool
    /// Speak replies aloud (in addition to the panel).
    var speakReplies: Bool
    /// Gate for the run_system_action tool (AppleScript/shell/open).
    var allowSystemControl: Bool
    /// Confirmation policy: tiered | confirmEverything | trust.
    var confirmTier: String

    static let `default` = VoiceConfig(
        enabled: false,
        model: "claude-opus-4-8",
        effort: "medium",
        maxTokens: 1024,
        wakeWord: .default,
        pushToTalkFallback: true,
        speakReplies: true,
        allowSystemControl: true,
        confirmTier: "tiered"
    )

    enum CodingKeys: String, CodingKey {
        case enabled, model, effort, maxTokens, wakeWord, pushToTalkFallback
        case speakReplies, allowSystemControl, confirmTier
    }

    init(enabled: Bool, model: String, effort: String, maxTokens: Int,
         wakeWord: VoiceWakeWordConfig, pushToTalkFallback: Bool,
         speakReplies: Bool, allowSystemControl: Bool, confirmTier: String) {
        self.enabled = enabled
        self.model = model
        self.effort = effort
        self.maxTokens = maxTokens
        self.wakeWord = wakeWord
        self.pushToTalkFallback = pushToTalkFallback
        self.speakReplies = speakReplies
        self.allowSystemControl = allowSystemControl
        self.confirmTier = confirmTier
    }

    init(from decoder: Decoder) throws {
        let d = VoiceConfig.default
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        effort = try c.decodeIfPresent(String.self, forKey: .effort) ?? d.effort
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? d.maxTokens
        wakeWord = try c.decodeIfPresent(VoiceWakeWordConfig.self, forKey: .wakeWord) ?? d.wakeWord
        pushToTalkFallback = try c.decodeIfPresent(Bool.self, forKey: .pushToTalkFallback) ?? d.pushToTalkFallback
        speakReplies = try c.decodeIfPresent(Bool.self, forKey: .speakReplies) ?? d.speakReplies
        allowSystemControl = try c.decodeIfPresent(Bool.self, forKey: .allowSystemControl) ?? d.allowSystemControl
        confirmTier = try c.decodeIfPresent(String.self, forKey: .confirmTier) ?? d.confirmTier
    }
}
```

Then modify `AppConfig` in the same file:
- Add stored property `var voice: VoiceConfig` after `missionControl`.
- Add `case voice` to `AppConfig.CodingKeys`.
- Add `voice: VoiceConfig = .default` parameter to the memberwise `init(...)` and assign it.
- In `AppConfig.init(from:)` add: `voice = try c.decodeIfPresent(VoiceConfig.self, forKey: .voice) ?? .default`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd brp && swift test --filter VoiceConfigTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add brp/Sources/BrotherPaul/Models.swift brp/Tests/BrotherPaulTests/VoiceConfigTests.swift
git commit -m "feat(brp): add VoiceConfig model with backward-compatible decoding"
```

---

### Task 2: JSONValue (dynamic tool-input value type)

**Files:**
- Create: `brp/Sources/BrotherPaul/Agent/JSONValue.swift`
- Test: `brp/Tests/BrotherPaulTests/JSONValueTests.swift`

**Interfaces:**
- Produces: `enum JSONValue: Codable, Equatable { case string(String), double(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null }` with helpers `var stringValue: String?`, `var intValue: Int?`, `var arrayValue: [JSONValue]?`, `var objectValue: [String: JSONValue]?`.

- [ ] **Step 1: Write the failing test**

```swift
// brp/Tests/BrotherPaulTests/JSONValueTests.swift
import XCTest
@testable import BrotherPaul

final class JSONValueTests: XCTestCase {

    func testDecodeMixedObject() throws {
        let json = #"{ "app": "Slack", "count": 3, "flag": true, "tags": ["a","b"] }"#.data(using: .utf8)!
        let value = try JSONDecoder().decode(JSONValue.self, from: json)
        let obj = try XCTUnwrap(value.objectValue)
        XCTAssertEqual(obj["app"]?.stringValue, "Slack")
        XCTAssertEqual(obj["count"]?.intValue, 3)
        XCTAssertEqual(obj["flag"], .bool(true))
        XCTAssertEqual(obj["tags"]?.arrayValue?.count, 2)
    }

    func testEncodeRoundTrips() throws {
        let value: JSONValue = .object(["k": .string("v"), "n": .double(2)])
        let data = try JSONEncoder().encode(value)
        let back = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(back, value)
    }

    func testIntValueFromWholeDouble() {
        XCTAssertEqual(JSONValue.double(8).intValue, 8)
        XCTAssertNil(JSONValue.string("x").intValue)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd brp && swift test --filter JSONValueTests`
Expected: FAIL to compile — `JSONValue` undefined.

- [ ] **Step 3: Implement JSONValue**

```swift
// brp/Sources/BrotherPaul/Agent/JSONValue.swift
import Foundation

/// A dynamically-typed JSON value, used for tool inputs Claude sends back
/// (whose shape isn't known at compile time) and for tool input_schema literals.
enum JSONValue: Codable, Equatable {
    case string(String)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    var stringValue: String? { if case .string(let s) = self { return s }; return nil }

    var intValue: Int? {
        if case .double(let d) = self, d.rounded() == d { return Int(d) }
        return nil
    }

    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .double(let d): try c.encode(d)
        case .bool(let b):   try c.encode(b)
        case .array(let a):  try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null:          try c.encodeNil()
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd brp && swift test --filter JSONValueTests`
Expected: PASS (3 tests).

> Note: `Bool` is decoded before `Double` because `JSONDecoder` will happily decode `true` as `1.0` otherwise.

- [ ] **Step 5: Commit**

```bash
git add brp/Sources/BrotherPaul/Agent/JSONValue.swift brp/Tests/BrotherPaulTests/JSONValueTests.swift
git commit -m "feat(brp): add JSONValue dynamic value type for tool inputs"
```

---

### Task 3: Agent core types (ToolCall, ExecutionOutcome, ToolRisk)

**Files:**
- Create: `brp/Sources/BrotherPaul/Agent/AgentTypes.swift`
- Test: covered by Task 4.

**Interfaces:**
- Produces: `struct ToolCall: Equatable { let id: String; let name: String; let input: [String: JSONValue] }`; `struct ExecutionOutcome: Equatable { let content: String; let isError: Bool; static func ok(_:) -> ExecutionOutcome; static func failure(_:) -> ExecutionOutcome }`; `enum ToolRisk { case safe, confirm }`.

- [ ] **Step 1: Write the implementation (no separate test — exercised by Tasks 4 & 7)**

```swift
// brp/Sources/BrotherPaul/Agent/AgentTypes.swift
import Foundation

/// A single tool invocation requested by Claude.
struct ToolCall: Equatable {
    let id: String              // the tool_use block id, echoed back in tool_result
    let name: String
    let input: [String: JSONValue]
}

/// The result of executing one tool, fed back to Claude as a tool_result.
struct ExecutionOutcome: Equatable {
    let content: String
    let isError: Bool

    static func ok(_ content: String) -> ExecutionOutcome { .init(content: content, isError: false) }
    static func failure(_ message: String) -> ExecutionOutcome { .init(content: message, isError: true) }
}

/// Confirmation tier for a tool call.
enum ToolRisk: Equatable {
    case safe       // run immediately
    case confirm    // require confirmation first
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd brp && swift build`
Expected: builds cleanly.

- [ ] **Step 3: Commit**

```bash
git add brp/Sources/BrotherPaul/Agent/AgentTypes.swift
git commit -m "feat(brp): add agent core types (ToolCall, ExecutionOutcome, ToolRisk)"
```

---

### Task 4: ToolRiskClassifier (the tiered-safety brain)

**Files:**
- Create: `brp/Sources/BrotherPaul/Agent/ToolRiskClassifier.swift`
- Test: `brp/Tests/BrotherPaulTests/ToolRiskClassifierTests.swift`

**Interfaces:**
- Consumes: `ToolCall`, `ToolRisk`, `JSONValue` (Tasks 2–3).
- Produces: `enum ToolRiskClassifier { static func risk(for call: ToolCall) -> ToolRisk; static func isDestructive(_ call: ToolCall) -> Bool }`. `isDestructive` is the always-confirm deny-list (honored even in the `trust` tier — tier resolution happens in Plan 2).

- [ ] **Step 1: Write the failing test**

```swift
// brp/Tests/BrotherPaulTests/ToolRiskClassifierTests.swift
import XCTest
@testable import BrotherPaul

final class ToolRiskClassifierTests: XCTestCase {

    private func call(_ name: String, _ input: [String: JSONValue]) -> ToolCall {
        ToolCall(id: "t1", name: name, input: input)
    }

    func testOpenAppIsSafe() {
        XCTAssertEqual(ToolRiskClassifier.risk(for: call("control_apps",
            ["action": .string("open_app"), "app": .string("Slack")])), .safe)
    }

    func testStartModeIsSafe() {
        XCTAssertEqual(ToolRiskClassifier.risk(for: call("control_apps",
            ["action": .string("start_mode"), "mode": .string("Deep Work")])), .safe)
    }

    func testCloseAppRequiresConfirm() {
        XCTAssertEqual(ToolRiskClassifier.risk(for: call("control_apps",
            ["action": .string("close_app"), "app": .string("Slack")])), .confirm)
    }

    func testEndModeRequiresConfirm() {
        XCTAssertEqual(ToolRiskClassifier.risk(for: call("control_apps",
            ["action": .string("end_mode"), "mode": .string("Full")])), .confirm)
    }

    func testWindowControlIsSafe() {
        XCTAssertEqual(ToolRiskClassifier.risk(for: call("control_windows",
            ["zone": .string("leftHalf")])), .safe)
    }

    func testQueryScheduleIsSafe() {
        XCTAssertEqual(ToolRiskClassifier.risk(for: call("query_schedule", [:])), .safe)
    }

    func testOpenUrlIsSafe() {
        XCTAssertEqual(ToolRiskClassifier.risk(for: call("run_system_action",
            ["kind": .string("open_url"), "payload": .string("https://x.com")])), .safe)
    }

    func testAppleScriptRequiresConfirm() {
        XCTAssertEqual(ToolRiskClassifier.risk(for: call("run_system_action",
            ["kind": .string("applescript"), "payload": .string("tell app \"Finder\" to quit")])), .confirm)
    }

    func testShellRequiresConfirm() {
        XCTAssertEqual(ToolRiskClassifier.risk(for: call("run_system_action",
            ["kind": .string("shell"), "payload": .string("ls")])), .confirm)
    }

    func testDestructiveShellIsFlagged() {
        XCTAssertTrue(ToolRiskClassifier.isDestructive(call("run_system_action",
            ["kind": .string("shell"), "payload": .string("rm -rf ~/Documents")])))
        XCTAssertTrue(ToolRiskClassifier.isDestructive(call("run_system_action",
            ["kind": .string("shell"), "payload": .string("sudo reboot")])))
        XCTAssertFalse(ToolRiskClassifier.isDestructive(call("run_system_action",
            ["kind": .string("shell"), "payload": .string("ls -la")])))
    }

    func testUnknownToolDefaultsToConfirm() {
        XCTAssertEqual(ToolRiskClassifier.risk(for: call("something_new", [:])), .confirm)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd brp && swift test --filter ToolRiskClassifierTests`
Expected: FAIL to compile — `ToolRiskClassifier` undefined.

- [ ] **Step 3: Implement the classifier**

```swift
// brp/Sources/BrotherPaul/Agent/ToolRiskClassifier.swift
import Foundation

enum ToolRiskClassifier {

    /// Shell/AppleScript fragments that must always be confirmed regardless of tier.
    private static let destructivePatterns: [String] = [
        "rm -rf", "rm -r ", "rm -f", "sudo ", "mkfs", "diskutil ", "dd ", "killall",
        ":(){", "shutdown", "reboot", "> /dev/", "chmod -r", "chown -r", "fdisk"
    ]

    static func risk(for call: ToolCall) -> ToolRisk {
        switch call.name {
        case "control_apps":
            switch call.input["action"]?.stringValue {
            case "open_app", "start_mode", "hide_others": return .safe
            case "close_app", "end_mode":                  return .confirm
            default:                                       return .confirm
            }
        case "control_windows":
            return .safe
        case "query_schedule":
            return .safe
        case "run_system_action":
            if isDestructive(call) { return .confirm }
            switch call.input["kind"]?.stringValue {
            case "open_url", "open_file": return .safe
            default:                      return .confirm   // applescript, shell, setting
            }
        default:
            return .confirm
        }
    }

    /// Always-confirm deny-list: true if the payload looks destructive.
    static func isDestructive(_ call: ToolCall) -> Bool {
        guard call.name == "run_system_action",
              let payload = call.input["payload"]?.stringValue?.lowercased() else { return false }
        return destructivePatterns.contains { payload.contains($0) }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd brp && swift test --filter ToolRiskClassifierTests`
Expected: PASS (11 tests).

- [ ] **Step 5: Commit**

```bash
git add brp/Sources/BrotherPaul/Agent/ToolRiskClassifier.swift brp/Tests/BrotherPaulTests/ToolRiskClassifierTests.swift
git commit -m "feat(brp): add ToolRiskClassifier for tiered tool-call safety"
```

---

### Task 5: SecretStore (Keychain abstraction for the API key)

**Files:**
- Create: `brp/Sources/BrotherPaul/Agent/SecretStore.swift`
- Test: `brp/Tests/BrotherPaulTests/SecretStoreTests.swift`

**Interfaces:**
- Produces: `protocol SecretStore { func get(_ key: String) -> String?; func set(_ value: String, for key: String); func delete(_ key: String) }`; `final class KeychainSecretStore: SecretStore` (real, uses `Security`); `final class InMemorySecretStore: SecretStore` (tests). Key constant: `enum SecretKey { static let anthropicAPIKey = "anthropic-api-key" }`.

- [ ] **Step 1: Write the failing test**

```swift
// brp/Tests/BrotherPaulTests/SecretStoreTests.swift
import XCTest
@testable import BrotherPaul

final class SecretStoreTests: XCTestCase {

    func testInMemoryStoreRoundTrips() {
        let store = InMemorySecretStore()
        XCTAssertNil(store.get(SecretKey.anthropicAPIKey))
        store.set("sk-ant-123", for: SecretKey.anthropicAPIKey)
        XCTAssertEqual(store.get(SecretKey.anthropicAPIKey), "sk-ant-123")
        store.delete(SecretKey.anthropicAPIKey)
        XCTAssertNil(store.get(SecretKey.anthropicAPIKey))
    }

    func testInMemoryStoreOverwrites() {
        let store = InMemorySecretStore()
        store.set("a", for: "k")
        store.set("b", for: "k")
        XCTAssertEqual(store.get("k"), "b")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd brp && swift test --filter SecretStoreTests`
Expected: FAIL to compile — `SecretStore`/`InMemorySecretStore` undefined.

- [ ] **Step 3: Implement SecretStore + both implementations**

```swift
// brp/Sources/BrotherPaul/Agent/SecretStore.swift
import Foundation
import Security

enum SecretKey {
    static let anthropicAPIKey = "anthropic-api-key"
}

protocol SecretStore {
    func get(_ key: String) -> String?
    func set(_ value: String, for key: String)
    func delete(_ key: String)
}

/// Test-only in-memory store. Not thread-safe — fine for tests.
final class InMemorySecretStore: SecretStore {
    private var storage: [String: String] = [:]
    func get(_ key: String) -> String? { storage[key] }
    func set(_ value: String, for key: String) { storage[key] = value }
    func delete(_ key: String) { storage[key] = nil }
}

/// Generic-password Keychain store, scoped by service name.
final class KeychainSecretStore: SecretStore {
    private let service = "com.brotherpaul.secrets"

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    func get(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    func set(_ value: String, for key: String) {
        delete(key)
        var q = query(key)
        q[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(q as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("BrotherPaul: keychain set failed for %@ (status %d)", key, Int(status))
        }
    }

    func delete(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd brp && swift test --filter SecretStoreTests`
Expected: PASS (2 tests). (Tests use the in-memory store only — the Keychain path is covered by manual verification, since SwiftPM test bundles may hit `errSecMissingEntitlement`.)

- [ ] **Step 5: Commit**

```bash
git add brp/Sources/BrotherPaul/Agent/SecretStore.swift brp/Tests/BrotherPaulTests/SecretStoreTests.swift
git commit -m "feat(brp): add SecretStore (Keychain + in-memory) for the API key"
```

---

### Task 6: Messages API wire models (Codable)

**Files:**
- Create: `brp/Sources/BrotherPaul/Agent/MessagesAPI.swift`
- Test: `brp/Tests/BrotherPaulTests/MessagesAPITests.swift`

**Interfaces:**
- Consumes: `JSONValue` (Task 2).
- Produces:
  - `enum APIContentBlock: Codable { case text(String); case toolUse(id: String, name: String, input: [String: JSONValue]); case toolResult(toolUseId: String, content: String, isError: Bool) }`
  - `struct APIMessage: Codable { let role: String; let content: [APIContentBlock] }`
  - `struct APIToolDefinition: Encodable { let name: String; let description: String; let input_schema: JSONValue }`
  - `struct MessagesRequest: Encodable { … }` and `struct MessagesResponse: Decodable { let content: [APIContentBlock]; let stop_reason: String? }`

- [ ] **Step 1: Write the failing test**

```swift
// brp/Tests/BrotherPaulTests/MessagesAPITests.swift
import XCTest
@testable import BrotherPaul

final class MessagesAPITests: XCTestCase {

    func testDecodesToolUseResponse() throws {
        let json = """
        { "content": [
            { "type": "text", "text": "Opening Slack." },
            { "type": "tool_use", "id": "toolu_1", "name": "control_apps",
              "input": { "action": "open_app", "app": "Slack" } }
          ],
          "stop_reason": "tool_use" }
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(MessagesResponse.self, from: json)
        XCTAssertEqual(resp.stop_reason, "tool_use")
        guard case .text(let t) = resp.content[0] else { return XCTFail("expected text") }
        XCTAssertEqual(t, "Opening Slack.")
        guard case .toolUse(let id, let name, let input) = resp.content[1] else { return XCTFail("expected tool_use") }
        XCTAssertEqual(id, "toolu_1")
        XCTAssertEqual(name, "control_apps")
        XCTAssertEqual(input["app"]?.stringValue, "Slack")
    }

    func testEncodesToolResultBlock() throws {
        let msg = APIMessage(role: "user", content: [
            .toolResult(toolUseId: "toolu_1", content: "Done.", isError: false)
        ])
        let data = try JSONEncoder().encode(msg)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let block = (obj["content"] as! [[String: Any]])[0]
        XCTAssertEqual(block["type"] as? String, "tool_result")
        XCTAssertEqual(block["tool_use_id"] as? String, "toolu_1")
        XCTAssertEqual(block["content"] as? String, "Done.")
    }

    func testRequestEncodesSystemCacheControlAndTools() throws {
        let req = MessagesRequest(
            model: "claude-opus-4-8",
            max_tokens: 1024,
            system: "You are Brother Paul.",
            tools: [APIToolDefinition(name: "control_apps", description: "d", input_schema: .object([:]))],
            messages: [APIMessage(role: "user", content: [.text("hi")])],
            effort: "medium"
        )
        let data = try JSONEncoder().encode(req)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let sys = obj["system"] as! [[String: Any]]
        XCTAssertEqual((sys[0]["cache_control"] as! [String: Any])["type"] as? String, "ephemeral")
        XCTAssertEqual((obj["thinking"] as! [String: Any])["type"] as? String, "adaptive")
        XCTAssertEqual((obj["output_config"] as! [String: Any])["effort"] as? String, "medium")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd brp && swift test --filter MessagesAPITests`
Expected: FAIL to compile — types undefined.

- [ ] **Step 3: Implement the wire models**

```swift
// brp/Sources/BrotherPaul/Agent/MessagesAPI.swift
import Foundation

enum APIContentBlock: Codable, Equatable {
    case text(String)
    case toolUse(id: String, name: String, input: [String: JSONValue])
    case toolResult(toolUseId: String, content: String, isError: Bool)

    private enum CodingKeys: String, CodingKey {
        case type, text, id, name, input, tool_use_id, content, is_error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "text":
            self = .text(try c.decode(String.self, forKey: .text))
        case "tool_use":
            self = .toolUse(
                id: try c.decode(String.self, forKey: .id),
                name: try c.decode(String.self, forKey: .name),
                input: try c.decode([String: JSONValue].self, forKey: .input))
        case "tool_result":
            self = .toolResult(
                toolUseId: try c.decode(String.self, forKey: .tool_use_id),
                content: try c.decode(String.self, forKey: .content),
                isError: try c.decodeIfPresent(Bool.self, forKey: .is_error) ?? false)
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                debugDescription: "Unknown content block type \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let t):
            try c.encode("text", forKey: .type)
            try c.encode(t, forKey: .text)
        case .toolUse(let id, let name, let input):
            try c.encode("tool_use", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(input, forKey: .input)
        case .toolResult(let toolUseId, let content, let isError):
            try c.encode("tool_result", forKey: .type)
            try c.encode(toolUseId, forKey: .tool_use_id)
            try c.encode(content, forKey: .content)
            try c.encode(isError, forKey: .is_error)
        }
    }
}

struct APIMessage: Codable, Equatable {
    let role: String
    let content: [APIContentBlock]
}

struct APIToolDefinition: Encodable {
    let name: String
    let description: String
    let input_schema: JSONValue
}

struct MessagesResponse: Decodable {
    let content: [APIContentBlock]
    let stop_reason: String?
}

struct MessagesRequest: Encodable {
    let model: String
    let max_tokens: Int
    let system: [SystemBlock]
    let tools: [APIToolDefinition]
    let messages: [APIMessage]
    let thinking: Thinking
    let output_config: OutputConfig

    init(model: String, max_tokens: Int, system: String,
         tools: [APIToolDefinition], messages: [APIMessage], effort: String) {
        self.model = model
        self.max_tokens = max_tokens
        self.system = [SystemBlock(text: system)]
        self.tools = tools
        self.messages = messages
        self.thinking = Thinking()
        self.output_config = OutputConfig(effort: effort)
    }

    struct SystemBlock: Encodable {
        let type = "text"
        let text: String
        let cache_control = CacheControl()
        struct CacheControl: Encodable { let type = "ephemeral" }
    }
    struct Thinking: Encodable {
        let type = "adaptive"
        let display = "omitted"
    }
    struct OutputConfig: Encodable {
        let effort: String
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd brp && swift test --filter MessagesAPITests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add brp/Sources/BrotherPaul/Agent/MessagesAPI.swift brp/Tests/BrotherPaulTests/MessagesAPITests.swift
git commit -m "feat(brp): add Anthropic Messages API Codable wire models"
```

---

### Task 7: ClaudeClient (the manual tool-use loop)

**Files:**
- Create: `brp/Sources/BrotherPaul/Agent/ClaudeClient.swift`
- Test: `brp/Tests/BrotherPaulTests/ClaudeClientTests.swift`

**Interfaces:**
- Consumes: `MessagesRequest`/`MessagesResponse`/`APIContentBlock`/`APIMessage`/`APIToolDefinition` (Task 6), `ToolCall`/`ExecutionOutcome` (Task 3), `ToolRiskClassifier` (Task 4), `SecretStore` (Task 5), `VoiceConfig` (Task 1).
- Produces:
  - `protocol MessagesTransport { func send(_ request: MessagesRequest) async throws -> MessagesResponse }`
  - `final class ClaudeClient` with `init(config: VoiceConfig, tools: [APIToolDefinition], systemPrompt: String, secrets: SecretStore, transport: MessagesTransport)` and
    `func send(_ transcript: String, confirm: @escaping (ToolCall) async -> Bool, execute: @escaping (ToolCall) async -> ExecutionOutcome) async throws -> String`
  - `enum ClaudeClientError: Error { case missingAPIKey, refused(String), httpError(Int) }`
  - `final class URLSessionTransport: MessagesTransport` (real HTTP).

- [ ] **Step 1: Write the failing test**

```swift
// brp/Tests/BrotherPaulTests/ClaudeClientTests.swift
import XCTest
@testable import BrotherPaul

private final class StubTransport: MessagesTransport {
    var responses: [MessagesResponse]
    private(set) var requestCount = 0
    init(_ responses: [MessagesResponse]) { self.responses = responses }
    func send(_ request: MessagesRequest) async throws -> MessagesResponse {
        defer { requestCount += 1 }
        return responses[requestCount]
    }
}

final class ClaudeClientTests: XCTestCase {

    private func makeClient(_ transport: MessagesTransport) -> ClaudeClient {
        let secrets = InMemorySecretStore()
        secrets.set("sk-ant-test", for: SecretKey.anthropicAPIKey)
        return ClaudeClient(config: .default, tools: [], systemPrompt: "sys",
                            secrets: secrets, transport: transport)
    }

    func testReturnsFinalTextWhenNoTools() async throws {
        let transport = StubTransport([
            MessagesResponse(content: [.text("Your next meeting is at 2pm.")], stop_reason: "end_turn")
        ])
        let client = makeClient(transport)
        let reply = try await client.send("what's next?",
            confirm: { _ in true }, execute: { _ in .ok("") })
        XCTAssertEqual(reply, "Your next meeting is at 2pm.")
    }

    func testExecutesSafeToolThenReturnsText() async throws {
        let transport = StubTransport([
            MessagesResponse(content: [
                .toolUse(id: "tu1", name: "control_windows", input: ["zone": .string("leftHalf")])
            ], stop_reason: "tool_use"),
            MessagesResponse(content: [.text("Done.")], stop_reason: "end_turn")
        ])
        let client = makeClient(transport)
        var confirmCalled = false
        var executed: [String] = []
        let reply = try await client.send("snap left",
            confirm: { _ in confirmCalled = true; return true },
            execute: { call in executed.append(call.name); return .ok("snapped") })
        XCTAssertEqual(reply, "Done.")
        XCTAssertFalse(confirmCalled)          // safe tool: no confirmation
        XCTAssertEqual(executed, ["control_windows"])
    }

    func testRiskyToolAsksConfirmationAndSkipsWhenDenied() async throws {
        let transport = StubTransport([
            MessagesResponse(content: [
                .toolUse(id: "tu1", name: "control_apps",
                         input: ["action": .string("close_app"), "app": .string("Slack")])
            ], stop_reason: "tool_use"),
            MessagesResponse(content: [.text("Okay, I left it open.")], stop_reason: "end_turn")
        ])
        let client = makeClient(transport)
        var executed = false
        let reply = try await client.send("close slack",
            confirm: { _ in false },                    // user denies
            execute: { _ in executed = true; return .ok("") })
        XCTAssertFalse(executed)                          // denied → not executed
        XCTAssertEqual(reply, "Okay, I left it open.")
    }

    func testMissingKeyThrows() async {
        let secrets = InMemorySecretStore()       // no key set
        let client = ClaudeClient(config: .default, tools: [], systemPrompt: "s",
                                  secrets: secrets, transport: StubTransport([]))
        do {
            _ = try await client.send("hi", confirm: { _ in true }, execute: { _ in .ok("") })
            XCTFail("expected missingAPIKey")
        } catch ClaudeClientError.missingAPIKey {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testRefusalThrows() async {
        let transport = StubTransport([MessagesResponse(content: [], stop_reason: "refusal")])
        let client = makeClient(transport)
        do {
            _ = try await client.send("hi", confirm: { _ in true }, execute: { _ in .ok("") })
            XCTFail("expected refused")
        } catch ClaudeClientError.refused {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd brp && swift test --filter ClaudeClientTests`
Expected: FAIL to compile — `ClaudeClient`, `MessagesTransport`, `ClaudeClientError` undefined.

- [ ] **Step 3: Implement ClaudeClient + URLSessionTransport**

```swift
// brp/Sources/BrotherPaul/Agent/ClaudeClient.swift
import Foundation

protocol MessagesTransport {
    func send(_ request: MessagesRequest) async throws -> MessagesResponse
}

enum ClaudeClientError: Error, Equatable {
    case missingAPIKey
    case refused(String)
    case httpError(Int)
}

final class ClaudeClient {
    private let config: VoiceConfig
    private let tools: [APIToolDefinition]
    private let systemPrompt: String
    private let secrets: SecretStore
    private let transport: MessagesTransport

    /// Conversation history, preserved across calls within one ClaudeClient instance.
    private var history: [APIMessage] = []

    /// Safety valve against runaway tool loops.
    private let maxIterations = 8

    init(config: VoiceConfig, tools: [APIToolDefinition], systemPrompt: String,
         secrets: SecretStore, transport: MessagesTransport) {
        self.config = config
        self.tools = tools
        self.systemPrompt = systemPrompt
        self.secrets = secrets
        self.transport = transport
    }

    /// Send a user transcript, run the tool-use loop, return the final spoken text.
    func send(_ transcript: String,
              confirm: @escaping (ToolCall) async -> Bool,
              execute: @escaping (ToolCall) async -> ExecutionOutcome) async throws -> String {
        guard secrets.get(SecretKey.anthropicAPIKey) != nil else { throw ClaudeClientError.missingAPIKey }

        history.append(APIMessage(role: "user", content: [.text(transcript)]))

        for _ in 0..<maxIterations {
            let request = MessagesRequest(
                model: config.model, max_tokens: config.maxTokens, system: systemPrompt,
                tools: tools, messages: history, effort: config.effort)
            let response = try await transport.send(request)

            if response.stop_reason == "refusal" {
                throw ClaudeClientError.refused(firstText(response.content) ?? "Request was refused.")
            }

            history.append(APIMessage(role: "assistant", content: response.content))

            let toolCalls = response.content.compactMap { block -> ToolCall? in
                if case .toolUse(let id, let name, let input) = block {
                    return ToolCall(id: id, name: name, input: input)
                }
                return nil
            }

            if toolCalls.isEmpty || response.stop_reason == "end_turn" {
                return firstText(response.content) ?? ""
            }

            var results: [APIContentBlock] = []
            for call in toolCalls {
                let outcome: ExecutionOutcome
                if ToolRiskClassifier.risk(for: call) == .confirm {
                    let approved = await confirm(call)
                    outcome = approved ? await execute(call) : .ok("User declined this action.")
                } else {
                    outcome = await execute(call)
                }
                results.append(.toolResult(toolUseId: call.id, content: outcome.content, isError: outcome.isError))
            }
            history.append(APIMessage(role: "user", content: results))
        }

        return "I wasn't able to finish that — it took too many steps."
    }

    private func firstText(_ blocks: [APIContentBlock]) -> String? {
        for block in blocks { if case .text(let t) = block { return t } }
        return nil
    }
}

/// Real HTTP transport against the Anthropic Messages API.
final class URLSessionTransport: MessagesTransport {
    private let secrets: SecretStore
    private let session: URLSession
    private let url = URL(string: "https://api.anthropic.com/v1/messages")!

    init(secrets: SecretStore, session: URLSession = .shared) {
        self.secrets = secrets
        self.session = session
    }

    func send(_ request: MessagesRequest) async throws -> MessagesResponse {
        guard let key = secrets.get(SecretKey.anthropicAPIKey) else { throw ClaudeClientError.missingAPIKey }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            NSLog("BrotherPaul: Anthropic API error %d — %@", http.statusCode,
                  String(data: data, encoding: .utf8) ?? "")
            throw ClaudeClientError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(MessagesResponse.self, from: data)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd brp && swift test --filter ClaudeClientTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add brp/Sources/BrotherPaul/Agent/ClaudeClient.swift brp/Tests/BrotherPaulTests/ClaudeClientTests.swift
git commit -m "feat(brp): add ClaudeClient manual tool-use loop + URLSession transport"
```

---

### Task 8: Expose single-app launch/quit on AppLauncher

**Files:**
- Modify: `brp/Sources/BrotherPaul/AppLauncher.swift`
- Test: `brp/Tests/BrotherPaulTests/AppLauncherSurfaceTests.swift` (compile-surface only)

**Interfaces:**
- Produces: `AppLauncher.launchApp(named: String)` (change from `private` to internal `static`), and new `@discardableResult static func quitApp(named: String) -> Bool` (quits a single running app by bundle id or localized name; never quits Brother Paul; returns true if a match was terminated).

- [ ] **Step 1: Write the failing test**

```swift
// brp/Tests/BrotherPaulTests/AppLauncherSurfaceTests.swift
import XCTest
@testable import BrotherPaul

final class AppLauncherSurfaceTests: XCTestCase {
    // Launching/quitting real apps can't run headless; this only guards the
    // public surface so executors (Task 9–10) can compile against it.
    func testQuitUnknownAppReturnsFalse() {
        XCTAssertFalse(AppLauncher.quitApp(named: "NoSuchApp_ZZZ_12345"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd brp && swift test --filter AppLauncherSurfaceTests`
Expected: FAIL to compile — `quitApp(named:)` undefined.

- [ ] **Step 3: Modify AppLauncher**

In `brp/Sources/BrotherPaul/AppLauncher.swift`:
- Change `private static func launchApp(named name: String)` to `static func launchApp(named name: String)`.
- Add this method (reuse the matching logic from `end(mode:)`):

```swift
/// Quit a single running app by bundle id or localized name. Never quits Brother Paul.
@discardableResult
static func quitApp(named name: String) -> Bool {
    let myBundle = Bundle.main.bundleIdentifier
    let matches = NSWorkspace.shared.runningApplications.filter { app in
        if app.bundleIdentifier == myBundle { return false }
        if let bid = app.bundleIdentifier, bid.caseInsensitiveCompare(name) == .orderedSame { return true }
        if let n = app.localizedName, n.caseInsensitiveCompare(name) == .orderedSame { return true }
        return false
    }
    if matches.isEmpty { return false }
    for app in matches { _ = app.terminate() }
    return true
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd brp && swift test --filter AppLauncherSurfaceTests`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add brp/Sources/BrotherPaul/AppLauncher.swift brp/Tests/BrotherPaulTests/AppLauncherSurfaceTests.swift
git commit -m "feat(brp): expose single-app launch/quit on AppLauncher for the agent"
```

---

### Task 9: Tool executors — app + window control

**Files:**
- Create: `brp/Sources/BrotherPaul/Agent/AppControlExecutor.swift`
- Create: `brp/Sources/BrotherPaul/Agent/WindowControlExecutor.swift`
- Test: `brp/Tests/BrotherPaulTests/AppControlExecutorTests.swift`

**Interfaces:**
- Consumes: `ToolCall`/`ExecutionOutcome` (Task 3), `JSONValue` (Task 2), `AppLauncher` (Task 8), `WindowSnapper`/`SnapZone` (existing), `ConfigManager` (existing).
- Produces:
  - `protocol ToolExecutor { @MainActor func execute(_ call: ToolCall) async -> ExecutionOutcome }`
  - `struct AppControlExecutor: ToolExecutor` — handles `control_apps`.
  - `struct WindowControlExecutor: ToolExecutor` — handles `control_windows`.

- [ ] **Step 1: Write the failing test**

```swift
// brp/Tests/BrotherPaulTests/AppControlExecutorTests.swift
import XCTest
@testable import BrotherPaul

final class AppControlExecutorTests: XCTestCase {

    @MainActor
    func testUnknownActionIsError() async {
        let outcome = await AppControlExecutor().execute(
            ToolCall(id: "1", name: "control_apps", input: ["action": .string("frobnicate")]))
        XCTAssertTrue(outcome.isError)
    }

    @MainActor
    func testStartUnknownModeIsError() async {
        let outcome = await AppControlExecutor().execute(
            ToolCall(id: "1", name: "control_apps",
                     input: ["action": .string("start_mode"), "mode": .string("NoSuchMode_ZZZ")]))
        XCTAssertTrue(outcome.isError)
        XCTAssertTrue(outcome.content.contains("NoSuchMode_ZZZ"))
    }

    @MainActor
    func testCloseUnknownAppReportsNotRunning() async {
        let outcome = await AppControlExecutor().execute(
            ToolCall(id: "1", name: "control_apps",
                     input: ["action": .string("close_app"), "app": .string("NoSuchApp_ZZZ_12345")]))
        XCTAssertFalse(outcome.isError)          // not an error — just nothing to close
        XCTAssertTrue(outcome.content.lowercased().contains("not running")
                   || outcome.content.lowercased().contains("wasn't running"))
    }

    @MainActor
    func testWindowControlRejectsUnknownZone() async {
        let outcome = await WindowControlExecutor().execute(
            ToolCall(id: "1", name: "control_windows", input: ["zone": .string("sideways")]))
        XCTAssertTrue(outcome.isError)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd brp && swift test --filter AppControlExecutorTests`
Expected: FAIL to compile — executors undefined.

- [ ] **Step 3: Implement the protocol + both executors**

```swift
// brp/Sources/BrotherPaul/Agent/AppControlExecutor.swift
import AppKit

protocol ToolExecutor {
    @MainActor func execute(_ call: ToolCall) async -> ExecutionOutcome
}

struct AppControlExecutor: ToolExecutor {
    @MainActor
    func execute(_ call: ToolCall) async -> ExecutionOutcome {
        let config = ConfigManager.shared.config
        switch call.input["action"]?.stringValue {
        case "open_app":
            guard let app = call.input["app"]?.stringValue else { return .failure("Missing 'app'.") }
            AppLauncher.launchApp(named: app)
            return .ok("Opened \(app).")

        case "close_app":
            guard let app = call.input["app"]?.stringValue else { return .failure("Missing 'app'.") }
            let quit = AppLauncher.quitApp(named: app)
            return .ok(quit ? "Closed \(app)." : "\(app) wasn't running.")

        case "start_mode":
            guard let name = call.input["mode"]?.stringValue else { return .failure("Missing 'mode'.") }
            guard let mode = config.mode(named: name) else { return .failure("No mode named \(name).") }
            AppLauncher.launch(mode: mode, hideOthers: config.hideOthersAfterLaunch)
            return .ok("Started the \(mode.name) session.")

        case "end_mode":
            guard let name = call.input["mode"]?.stringValue else { return .failure("Missing 'mode'.") }
            guard let mode = config.mode(named: name) else { return .failure("No mode named \(name).") }
            AppLauncher.end(mode: mode)
            return .ok("Ended the \(mode.name) session.")

        case "hide_others":
            NSApp.hideOtherApplications(nil)
            return .ok("Hid the other apps.")

        default:
            return .failure("Unknown control_apps action.")
        }
    }
}
```

```swift
// brp/Sources/BrotherPaul/Agent/WindowControlExecutor.swift
import AppKit

struct WindowControlExecutor: ToolExecutor {
    @MainActor
    func execute(_ call: ToolCall) async -> ExecutionOutcome {
        guard let zoneName = call.input["zone"]?.stringValue,
              let zone = SnapZone(rawValue: zoneName) else {
            return .failure("Unknown window zone. Valid zones: \(SnapZone.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        // Optionally focus a named app first so the right window gets snapped.
        if let app = call.input["app"]?.stringValue {
            AppLauncher.launchApp(named: app)
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        let ok = WindowSnapper.snap(to: zone)
        return ok ? .ok("Snapped the window to \(zone.displayName).")
                  : .failure("Couldn't snap the window — check Accessibility permission or focus a window first.")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd brp && swift test --filter AppControlExecutorTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add brp/Sources/BrotherPaul/Agent/AppControlExecutor.swift brp/Sources/BrotherPaul/Agent/WindowControlExecutor.swift brp/Tests/BrotherPaulTests/AppControlExecutorTests.swift
git commit -m "feat(brp): add app + window control tool executors"
```

---

### Task 10: Tool executors — schedule query + system action

**Files:**
- Create: `brp/Sources/BrotherPaul/Agent/ScheduleQueryExecutor.swift`
- Create: `brp/Sources/BrotherPaul/Agent/SystemControlExecutor.swift`
- Test: `brp/Tests/BrotherPaulTests/SystemControlExecutorTests.swift`

**Interfaces:**
- Consumes: `ToolExecutor`/`ToolCall`/`ExecutionOutcome` (Tasks 3, 9), `MissionControlCoordinator` + `Digest`/`DigestItem`/`SectionResult` (existing — **read `brp/Sources/BrotherPaul/MissionControlModels.swift` first** to confirm `DigestItem`'s exact property names before writing the formatter), `VoiceConfig` (Task 1).
- Produces: `struct ScheduleQueryExecutor: ToolExecutor` (`query_schedule`); `struct SystemControlExecutor: ToolExecutor` (`run_system_action`, gated by `allowSystemControl`).

- [ ] **Step 1: Confirm DigestItem's shape**

Read `brp/Sources/BrotherPaul/MissionControlModels.swift`. Confirm `DigestItem` exposes `title`, optional `subtitle`, optional `timestamp`, and `Digest` exposes `events`/`emails`/`notifications` as `SectionResult` with `.items: [DigestItem]`. If property names differ, adjust the formatter in Step 3 accordingly.

- [ ] **Step 2: Write the failing test**

```swift
// brp/Tests/BrotherPaulTests/SystemControlExecutorTests.swift
import XCTest
@testable import BrotherPaul

final class SystemControlExecutorTests: XCTestCase {

    @MainActor
    func testDisallowedWhenSystemControlOff() async {
        var cfg = VoiceConfig.default
        cfg.allowSystemControl = false
        let exec = SystemControlExecutor(allowSystemControl: cfg.allowSystemControl)
        let outcome = await exec.execute(ToolCall(id: "1", name: "run_system_action",
            input: ["kind": .string("open_url"), "payload": .string("https://x.com")]))
        XCTAssertTrue(outcome.isError)
        XCTAssertTrue(outcome.content.lowercased().contains("disabled"))
    }

    @MainActor
    func testUnknownKindIsError() async {
        let exec = SystemControlExecutor(allowSystemControl: true)
        let outcome = await exec.execute(ToolCall(id: "1", name: "run_system_action",
            input: ["kind": .string("teleport"), "payload": .string("x")]))
        XCTAssertTrue(outcome.isError)
    }

    @MainActor
    func testShellRunsAndCapturesOutput() async {
        let exec = SystemControlExecutor(allowSystemControl: true)
        let outcome = await exec.execute(ToolCall(id: "1", name: "run_system_action",
            input: ["kind": .string("shell"), "payload": .string("echo hello-brp")]))
        XCTAssertFalse(outcome.isError)
        XCTAssertTrue(outcome.content.contains("hello-brp"))
    }
}
```

- [ ] **Step 3: Implement both executors**

```swift
// brp/Sources/BrotherPaul/Agent/ScheduleQueryExecutor.swift
import Foundation

struct ScheduleQueryExecutor: ToolExecutor {
    @MainActor
    func execute(_ call: ToolCall) async -> ExecutionOutcome {
        let coordinator = MissionControlCoordinator()
        await coordinator.refresh()
        guard let digest = coordinator.digest else {
            return .ok("I couldn't load your schedule right now.")
        }

        let df = DateFormatter()
        df.dateFormat = "EEE h:mm a"

        func format(_ section: SectionResult, label: String, limit: Int) -> String {
            let lines = section.items.prefix(limit).map { item -> String in
                let when = item.timestamp.map { " (\(df.string(from: $0)))" } ?? ""
                let sub = item.subtitle.map { " — \($0)" } ?? ""
                return "• \(item.title)\(sub)\(when)"
            }
            return lines.isEmpty ? "\(label): nothing." : "\(label):\n" + lines.joined(separator: "\n")
        }

        let sources = Set((call.input["sources"]?.arrayValue ?? []).compactMap { $0.stringValue })
        let wantAll = sources.isEmpty
        var parts: [String] = []
        if wantAll || sources.contains("calendar") { parts.append(format(digest.events, label: "Upcoming events", limit: 5)) }
        if wantAll || sources.contains("email") { parts.append(format(digest.emails, label: "Priority email", limit: 5)) }
        if sources.contains("notifications") { parts.append(format(digest.notifications, label: "Recent notifications", limit: 5)) }

        return .ok(parts.joined(separator: "\n\n"))
    }
}
```

```swift
// brp/Sources/BrotherPaul/Agent/SystemControlExecutor.swift
import AppKit

struct SystemControlExecutor: ToolExecutor {
    let allowSystemControl: Bool

    @MainActor
    func execute(_ call: ToolCall) async -> ExecutionOutcome {
        guard allowSystemControl else {
            return .failure("System control is disabled in Brother Paul's settings.")
        }
        guard let payload = call.input["payload"]?.stringValue else { return .failure("Missing 'payload'.") }

        switch call.input["kind"]?.stringValue {
        case "open_url":
            guard let url = URL(string: payload) else { return .failure("Invalid URL.") }
            NSWorkspace.shared.open(url)
            return .ok("Opened \(payload).")

        case "open_file":
            NSWorkspace.shared.open(URL(fileURLWithPath: (payload as NSString).expandingTildeInPath))
            return .ok("Opened \(payload).")

        case "applescript":
            var error: NSDictionary?
            let script = NSAppleScript(source: payload)
            let result = script?.executeAndReturnError(&error)
            if let error = error { return .failure("AppleScript error: \(error)") }
            return .ok(result?.stringValue ?? "Ran the AppleScript.")

        case "shell":
            return runShell(payload)

        default:
            return .failure("Unknown run_system_action kind.")
        }
    }

    private func runShell(_ command: String) -> ExecutionOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return process.terminationStatus == 0
                ? .ok(output.isEmpty ? "Done." : output)
                : .failure("Command exited \(process.terminationStatus): \(output)")
        } catch {
            return .failure("Couldn't run the command: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd brp && swift test --filter SystemControlExecutorTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add brp/Sources/BrotherPaul/Agent/ScheduleQueryExecutor.swift brp/Sources/BrotherPaul/Agent/SystemControlExecutor.swift brp/Tests/BrotherPaulTests/SystemControlExecutorTests.swift
git commit -m "feat(brp): add schedule-query + system-control tool executors"
```

---

### Task 11: AgentTools registry (schemas + dispatch)

**Files:**
- Create: `brp/Sources/BrotherPaul/Agent/AgentTools.swift`
- Test: `brp/Tests/BrotherPaulTests/AgentToolsTests.swift`

**Interfaces:**
- Consumes: `APIToolDefinition`/`JSONValue` (Tasks 2, 6), all executors (Tasks 9–10), `VoiceConfig` (Task 1).
- Produces:
  - `enum AgentTools { static func definitions() -> [APIToolDefinition]; static let systemPrompt: String }`
  - `final class AgentToolRegistry` with `init(allowSystemControl: Bool)` and `@MainActor func dispatch(_ call: ToolCall) async -> ExecutionOutcome` routing each tool name to its executor; unknown names → `.failure`.

- [ ] **Step 1: Write the failing test**

```swift
// brp/Tests/BrotherPaulTests/AgentToolsTests.swift
import XCTest
@testable import BrotherPaul

final class AgentToolsTests: XCTestCase {

    func testAllFourToolsAreDefined() {
        let names = Set(AgentTools.definitions().map(\.name))
        XCTAssertEqual(names, ["control_apps", "control_windows", "query_schedule", "run_system_action"])
    }

    func testEveryToolHasObjectSchema() {
        for tool in AgentTools.definitions() {
            XCTAssertFalse(tool.description.isEmpty, "\(tool.name) needs a description")
            guard case .object(let schema) = tool.input_schema else {
                return XCTFail("\(tool.name) input_schema must be an object")
            }
            XCTAssertEqual(schema["type"]?.stringValue, "object")
        }
    }

    @MainActor
    func testDispatchUnknownToolIsError() async {
        let registry = AgentToolRegistry(allowSystemControl: true)
        let outcome = await registry.dispatch(ToolCall(id: "1", name: "nope", input: [:]))
        XCTAssertTrue(outcome.isError)
    }

    @MainActor
    func testDispatchRoutesControlWindows() async {
        let registry = AgentToolRegistry(allowSystemControl: true)
        // Unknown zone → WindowControlExecutor returns an error; proves routing reached it.
        let outcome = await registry.dispatch(
            ToolCall(id: "1", name: "control_windows", input: ["zone": .string("nope")]))
        XCTAssertTrue(outcome.isError)
        XCTAssertTrue(outcome.content.contains("zone"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd brp && swift test --filter AgentToolsTests`
Expected: FAIL to compile — `AgentTools`/`AgentToolRegistry` undefined.

- [ ] **Step 3: Implement AgentTools + registry**

```swift
// brp/Sources/BrotherPaul/Agent/AgentTools.swift
import Foundation

enum AgentTools {

    static let systemPrompt = """
    You are Brother Paul, a concise, friendly macOS work assistant. You can open and \
    close apps, start and end work-session modes, snap windows, answer questions about \
    the user's calendar and email, and run system actions. Prefer the most specific \
    tool. Keep spoken replies short — one or two sentences. Only call a tool when the \
    user clearly wants an action or current information; otherwise just answer.
    """

    static func definitions() -> [APIToolDefinition] {
        [
            APIToolDefinition(
                name: "control_apps",
                description: "Open or close an app, or start/end a work-session mode. Use when the user wants to launch, quit, or switch their work environment.",
                input_schema: objectSchema(
                    properties: [
                        "action": stringEnum(["open_app", "close_app", "start_mode", "end_mode", "hide_others"], "What to do."),
                        "app": stringProp("App name, for open_app/close_app (e.g. 'Slack')."),
                        "mode": stringProp("Mode name, for start_mode/end_mode (e.g. 'Deep Work').")
                    ],
                    required: ["action"])),

            APIToolDefinition(
                name: "control_windows",
                description: "Snap the focused window (or a named app's window) to a screen zone.",
                input_schema: objectSchema(
                    properties: [
                        "zone": stringEnum(SnapZone.allCases.map(\.rawValue), "Target zone."),
                        "app": stringProp("Optional app to focus first.")
                    ],
                    required: ["zone"])),

            APIToolDefinition(
                name: "query_schedule",
                description: "Read the user's upcoming calendar events, priority email, and recent notifications. Use to answer questions about their day.",
                input_schema: objectSchema(
                    properties: [
                        "sources": .object([
                            "type": .string("array"),
                            "items": .object(["type": .string("string")]),
                            "description": .string("Subset of ['calendar','email','notifications']. Omit for calendar+email.")
                        ]),
                        "lookbackHours": .object([
                            "type": .string("number"),
                            "description": .string("Window in hours.")
                        ])
                    ],
                    required: [])),

            APIToolDefinition(
                name: "run_system_action",
                description: "Open a URL or file, or run an AppleScript or shell command. Use only when no more specific tool fits.",
                input_schema: objectSchema(
                    properties: [
                        "kind": stringEnum(["open_url", "open_file", "applescript", "shell"], "Action kind."),
                        "payload": stringProp("URL, file path, AppleScript source, or shell command.")
                    ],
                    required: ["kind", "payload"]))
        ]
    }

    // MARK: - schema helpers

    private static func objectSchema(properties: [String: JSONValue], required: [String]) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map { .string($0) })
        ])
    }
    private static func stringProp(_ description: String) -> JSONValue {
        .object(["type": .string("string"), "description": .string(description)])
    }
    private static func stringEnum(_ values: [String], _ description: String) -> JSONValue {
        .object([
            "type": .string("string"),
            "enum": .array(values.map { .string($0) }),
            "description": .string(description)
        ])
    }
}

/// Routes a ToolCall to the executor that handles its tool name.
final class AgentToolRegistry {
    private let allowSystemControl: Bool
    init(allowSystemControl: Bool) { self.allowSystemControl = allowSystemControl }

    @MainActor
    func dispatch(_ call: ToolCall) async -> ExecutionOutcome {
        switch call.name {
        case "control_apps":       return await AppControlExecutor().execute(call)
        case "control_windows":    return await WindowControlExecutor().execute(call)
        case "query_schedule":     return await ScheduleQueryExecutor().execute(call)
        case "run_system_action":  return await SystemControlExecutor(allowSystemControl: allowSystemControl).execute(call)
        default:                   return .failure("Unknown tool: \(call.name).")
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd brp && swift test --filter AgentToolsTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add brp/Sources/BrotherPaul/Agent/AgentTools.swift brp/Tests/BrotherPaulTests/AgentToolsTests.swift
git commit -m "feat(brp): add AgentTools schemas + dispatch registry"
```

---

### Task 12: Full-suite green + plan-2 seam

**Files:**
- Modify: `brp/bin/test.sh` (only if it filters tests by name — confirm it runs the whole suite; otherwise no change).
- Test: whole suite.

**Interfaces:**
- Produces: a verified, fully green agent core. `ClaudeClient` + `AgentToolRegistry` + `KeychainSecretStore` are the seam Plan 2's `VoiceSessionController` will wire `confirm`/`execute` into:
  - `confirm` → voice/panel prompt
  - `execute` → `registry.dispatch(_:)` (on the main actor)

- [ ] **Step 1: Run the entire test suite**

Run: `cd brp && swift test`
Expected: PASS — all existing tests plus the new `VoiceConfigTests`, `JSONValueTests`, `ToolRiskClassifierTests`, `SecretStoreTests`, `MessagesAPITests`, `ClaudeClientTests`, `AppLauncherSurfaceTests`, `AppControlExecutorTests`, `SystemControlExecutorTests`, `AgentToolsTests`.

- [ ] **Step 2: Build the app target**

Run: `cd brp && swift build`
Expected: builds cleanly (the Agent core is unused by the UI yet — that's expected; Plan 2 wires it in).

- [ ] **Step 3: Commit (if any test-script change was needed)**

```bash
git add -A
git commit -m "test(brp): verify agent core suite is green"
```

---

## Self-Review

**Spec coverage (against `2026-06-18-voice-agent-design.md`):**
- §2 cloud LLM brain → Tasks 6–7 (ClaudeClient over Messages API). ✓
- §3 client-side tool-use loop → Task 7. ✓
- §4 `ClaudeClient`, `AgentTools`, `ToolExecutor`, `ToolRiskClassifier` → Tasks 4, 7, 9–11. ✓
- §5 four tools mapping to the pillars → Tasks 9–11 (+ Task 8 exposes AppLauncher). ✓
- §6 `VoiceConfig`, Keychain key storage → Tasks 1, 5. ✓
- §7 tiered safety, deny-list, `is_error` tool results, refusal handling → Tasks 4, 7, 9–10. ✓
- §8 testing (ToolRiskClassifier, AgentTools, ClaudeClient with mock transport) → Tasks 4, 7, 11. ✓
- **Deferred to Plan 2** (voice front-end): `WakeWordEngine`, `SpeechTranscriber`, `SpeechSynthesizer`, `VoiceSessionController`, `VoicePanelWindow`/`View`, `AppDelegate` wiring, menu items, `Info.plist` usage strings, push-to-talk fallback, confirm-tier resolution (`tiered`/`confirmEverything`/`trust`). These consume the Task-12 seam.

**Placeholder scan:** none — every code step is complete.

**Type consistency:** `ToolCall`/`ExecutionOutcome`/`ToolRisk` (Task 3) are used identically in Tasks 4, 7, 9–11; `APIContentBlock`/`APIMessage`/`MessagesRequest`/`MessagesResponse` (Task 6) match `ClaudeClient`'s usage (Task 7); `SecretStore`/`SecretKey.anthropicAPIKey` (Task 5) match `ClaudeClient` + `URLSessionTransport`; `ToolExecutor.execute(_:)` (Task 9) signature matches all four executors and `AgentToolRegistry.dispatch` (Task 11).
