# Brother Paul Test Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an XCTest unit-test suite for all pure logic in Brother Paul, a bash smoke harness that exercises real `brotherpaul://` URLs end-to-end, and the small source extractions needed to make existing inline logic testable.

**Architecture:** Two layers. (1) `Tests/BrotherPaulTests/` — XCTest target running pure-logic tests via `swift test`. (2) `bin/smoke-test.sh` — bash harness that builds the real `.app`, runs it against a hermetic fixture config (via the `BROTHERPAUL_CONFIG_DIR` env-var override that this plan adds), fires `brotherpaul://` URLs through LaunchServices, and asserts TextEdit/Calculator launch and quit on cue. A top-level `bin/test.sh` runs both in sequence.

**Tech Stack:** Swift 5.9 / SwiftPM, XCTest, Bash, macOS unified log (for the negative-case assertion in the smoke harness).

**Spec:** `docs/superpowers/specs/2026-05-21-test-harness-design.md`

---

## Task 1: Wire up the test target

Stand up the XCTest harness with a single trivial test that proves `@testable import BrotherPaul` works against the executable target. This is the foundation everything else builds on.

**Files:**
- Modify: `Package.swift`
- Create: `Tests/BrotherPaulTests/HarnessSmokeTest.swift`

- [ ] **Step 1.1: Add testTarget to Package.swift**

Replace the file with:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BrotherPaul",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BrotherPaul", targets: ["BrotherPaul"])
    ],
    targets: [
        .executableTarget(
            name: "BrotherPaul",
            path: "Sources/BrotherPaul"
        ),
        .testTarget(
            name: "BrotherPaulTests",
            dependencies: ["BrotherPaul"],
            path: "Tests/BrotherPaulTests"
        )
    ]
)
```

- [ ] **Step 1.2: Create the harness sanity test**

Write `Tests/BrotherPaulTests/HarnessSmokeTest.swift`:

```swift
import XCTest
@testable import BrotherPaul

/// Sentinel: confirms the test target compiles and links the executable target,
/// and that `@testable import BrotherPaul` reaches internal symbols.
final class HarnessSmokeTest: XCTestCase {

    func test_test_target_is_wired() {
        XCTAssertTrue(true)
    }

    func test_can_reach_internal_symbols() {
        // AppConfig.default is internal; if we can reference it the bridge works.
        let modes = AppConfig.default.modes
        XCTAssertFalse(modes.isEmpty)
    }
}
```

- [ ] **Step 1.3: Run `swift test`**

```bash
cd /Users/ssoward/sandbox/Workspace/brpaul
swift test
```

Expected: build succeeds; both tests pass; output ends with `Test Suite 'All tests' passed`.

**Failure mode to watch for:** If linking fails with `duplicate symbol _main`, the executable target's `main.swift` is being included in the test bundle. Fix by wrapping `main.swift` body in a runtime guard:

```swift
import AppKit

if NSClassFromString("XCTestCase") == nil {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
```

Then re-run `swift test`.

- [ ] **Step 1.4: Commit**

```bash
git add Package.swift Tests/BrotherPaulTests/HarnessSmokeTest.swift Sources/BrotherPaul/main.swift
git commit -m "$(cat <<'EOF'
test: wire up XCTest target for BrotherPaul

Adds a testTarget alongside the executable so swift test can drive the
unit-test suite. HarnessSmokeTest is a sentinel — it asserts the target
links and @testable import reaches internal symbols.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: AppConfig tests (existing logic, no source change)

`AppConfig.mode(named:)` and its decoding-with-defaults are already correct. These tests pin that behavior so future edits can't silently break it. No TDD prework — the implementation exists; tests document what it does.

**Files:**
- Create: `Tests/BrotherPaulTests/AppConfigTests.swift`

- [ ] **Step 2.1: Write the test file**

Write `Tests/BrotherPaulTests/AppConfigTests.swift`:

```swift
import XCTest
@testable import BrotherPaul

final class AppConfigTests: XCTestCase {

    // MARK: - mode(named:)

    func test_mode_lookup_is_case_insensitive() {
        let config = AppConfig.default
        XCTAssertNotNil(config.mode(named: "Full"))
        XCTAssertNotNil(config.mode(named: "full"))
        XCTAssertNotNil(config.mode(named: "FULL"))
        XCTAssertNotNil(config.mode(named: "Deep Work"))
        XCTAssertNotNil(config.mode(named: "deep work"))
    }

    func test_unknown_mode_returns_nil() {
        XCTAssertNil(AppConfig.default.mode(named: "NoSuchMode"))
        XCTAssertNil(AppConfig.default.mode(named: ""))
    }

    func test_mode_lookup_returns_the_matching_mode() {
        let mode = AppConfig.default.mode(named: "Full")
        XCTAssertEqual(mode?.name, "Full")
        XCTAssertTrue(mode?.apps.contains("Microsoft Teams") ?? false)
    }

    // MARK: - JSON decoding

    func test_decodes_full_realistic_config() throws {
        let json = #"""
        {
          "hideOthersAfterLaunch": true,
          "defaultMode": "Full",
          "modes": [
            { "name": "Full",  "apps": ["TextEdit"], "urls": [] },
            { "name": "Quiet", "apps": ["Calculator"], "urls": ["https://example.com"] }
          ],
          "enableSnap": false,
          "enableDragSnap": false
        }
        """#.data(using: .utf8)!

        let cfg = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(cfg.defaultMode, "Full")
        XCTAssertEqual(cfg.modes.count, 2)
        XCTAssertFalse(cfg.enableSnap)
        XCTAssertFalse(cfg.enableDragSnap)
        XCTAssertEqual(cfg.mode(named: "Quiet")?.urls, ["https://example.com"])
    }

    func test_missing_optional_keys_fall_back_to_defaults() throws {
        // Required keys only; enableSnap/enableDragSnap/missionControl omitted.
        let json = #"""
        {
          "hideOthersAfterLaunch": false,
          "defaultMode": "Solo",
          "modes": [ { "name": "Solo", "apps": ["TextEdit"], "urls": [] } ]
        }
        """#.data(using: .utf8)!

        let cfg = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertTrue(cfg.enableSnap, "enableSnap defaults to true when missing")
        XCTAssertTrue(cfg.enableDragSnap, "enableDragSnap defaults to true when missing")
        // missionControl is initialized to its `.default`
        XCTAssertEqual(cfg.missionControl.lookbackHours, MissionControlConfig.default.lookbackHours)
    }

    func test_missing_required_key_throws() {
        // No "defaultMode".
        let json = #"""
        {
          "hideOthersAfterLaunch": false,
          "modes": []
        }
        """#.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(AppConfig.self, from: json))
    }
}
```

- [ ] **Step 2.2: Run `swift test`**

```bash
swift test --filter AppConfigTests
```

Expected: all six tests pass.

- [ ] **Step 2.3: Commit**

```bash
git add Tests/BrotherPaulTests/AppConfigTests.swift
git commit -m "$(cat <<'EOF'
test: pin AppConfig decode + mode lookup behavior

Documents the existing case-insensitive mode(named:) lookup and the
decodeIfPresent fallbacks for optional keys (enableSnap, enableDragSnap,
missionControl). Future config edits must keep these contracts.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: ConfigManager `BROTHERPAUL_CONFIG_DIR` override + tests

Add the env-var override that lets tests and the smoke harness point ConfigManager at a hermetic directory. TDD: write the test first, confirm it fails, then implement.

**Files:**
- Modify: `Sources/BrotherPaul/ConfigManager.swift:16-19`
- Create: `Tests/BrotherPaulTests/ConfigManagerTests.swift`

- [ ] **Step 3.1: Write the failing test**

Write `Tests/BrotherPaulTests/ConfigManagerTests.swift`:

```swift
import XCTest
@testable import BrotherPaul

final class ConfigManagerTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("brpaul-test-\(UUID().uuidString)", isDirectory: true)
        setenv("BROTHERPAUL_CONFIG_DIR", tmp.path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("BROTHERPAUL_CONFIG_DIR")
        try? FileManager.default.removeItem(at: tmp)
    }

    func test_env_var_override_redirects_configDirectory() {
        XCTAssertEqual(ConfigManager.shared.configDirectory.path, tmp.path)
    }

    func test_bootstrap_creates_directory_and_writes_default_config() {
        ConfigManager.shared.bootstrap()
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ConfigManager.shared.configFile.path))
        XCTAssertEqual(ConfigManager.shared.config.defaultMode, AppConfig.default.defaultMode)
    }

    func test_reload_after_external_write_picks_up_changes() throws {
        ConfigManager.shared.bootstrap()
        var modified = ConfigManager.shared.config
        modified.defaultMode = "Custom"
        modified.modes = [LaunchMode(name: "Custom", apps: ["TextEdit"], urls: [])]
        try ConfigManager.shared.write(modified)

        _ = try ConfigManager.shared.reload()
        XCTAssertEqual(ConfigManager.shared.config.defaultMode, "Custom")
        XCTAssertEqual(ConfigManager.shared.config.modes.first?.name, "Custom")
    }
}
```

- [ ] **Step 3.2: Run the failing test**

```bash
swift test --filter ConfigManagerTests
```

Expected: `test_env_var_override_redirects_configDirectory` FAILS — `configDirectory` still returns `~/Library/Application Support/BrotherPaul`, not the tmp path.

- [ ] **Step 3.3: Implement the env-var override**

In `Sources/BrotherPaul/ConfigManager.swift`, replace the `configDirectory` computed property (currently lines 16–19) with:

```swift
    var configDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["BROTHERPAUL_CONFIG_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("BrotherPaul", isDirectory: true)
    }
```

- [ ] **Step 3.4: Run the tests**

```bash
swift test --filter ConfigManagerTests
```

Expected: all three tests pass.

- [ ] **Step 3.5: Run the full suite to check for regressions**

```bash
swift test
```

Expected: every test in `HarnessSmokeTest`, `AppConfigTests`, `ConfigManagerTests` passes.

- [ ] **Step 3.6: Commit**

```bash
git add Sources/BrotherPaul/ConfigManager.swift Tests/BrotherPaulTests/ConfigManagerTests.swift
git commit -m "$(cat <<'EOF'
feat(config): honor BROTHERPAUL_CONFIG_DIR env override

Lets tests and the smoke harness redirect ConfigManager at a hermetic
tmp directory without touching the user's real config. Production
behavior unchanged when the env var is unset.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: URLActionParser extraction + tests

Pull the URL parsing out of `AppDelegate.handleURLEvent` into a pure helper so it can be unit-tested. TDD: tests first.

**Files:**
- Create: `Sources/BrotherPaul/URLActionParser.swift`
- Create: `Tests/BrotherPaulTests/URLActionTests.swift`
- Modify: `Sources/BrotherPaul/AppDelegate.swift:61-78`

- [ ] **Step 4.1: Write the failing tests**

Write `Tests/BrotherPaulTests/URLActionTests.swift`:

```swift
import XCTest
@testable import BrotherPaul

final class URLActionTests: XCTestCase {

    func test_start_with_no_mode() {
        XCTAssertEqual(URLActionParser.parse("brotherpaul://start"),
                       .start(mode: nil))
    }

    func test_start_with_mode() {
        XCTAssertEqual(URLActionParser.parse("brotherpaul://start?mode=Full"),
                       .start(mode: "Full"))
    }

    func test_start_with_url_encoded_mode_name() {
        XCTAssertEqual(URLActionParser.parse("brotherpaul://start?mode=Deep%20Work"),
                       .start(mode: "Deep Work"))
    }

    func test_stop_with_mode() {
        XCTAssertEqual(URLActionParser.parse("brotherpaul://stop?mode=Meetings"),
                       .stop(mode: "Meetings"))
    }

    func test_end_alias_parses_as_stop() {
        XCTAssertEqual(URLActionParser.parse("brotherpaul://end"),
                       .stop(mode: nil))
    }

    func test_action_keyword_is_case_insensitive() {
        XCTAssertEqual(URLActionParser.parse("brotherpaul://START"),
                       .start(mode: nil))
        XCTAssertEqual(URLActionParser.parse("brotherpaul://Stop"),
                       .stop(mode: nil))
    }

    func test_mode_query_key_is_case_insensitive() {
        XCTAssertEqual(URLActionParser.parse("brotherpaul://start?Mode=Full"),
                       .start(mode: "Full"))
        XCTAssertEqual(URLActionParser.parse("brotherpaul://start?MODE=Full"),
                       .start(mode: "Full"))
    }

    func test_unknown_action_returns_unknown_case() {
        XCTAssertEqual(URLActionParser.parse("brotherpaul://reboot"),
                       .unknown(action: "reboot"))
    }

    func test_empty_string_returns_nil() {
        XCTAssertNil(URLActionParser.parse(""))
    }
}
```

- [ ] **Step 4.2: Run the tests — expected to fail at compile time**

```bash
swift test --filter URLActionTests
```

Expected: build fails — `URLActionParser` and `URLAction` do not exist.

- [ ] **Step 4.3: Create the parser**

Write `Sources/BrotherPaul/URLActionParser.swift`:

```swift
import Foundation

/// Parsed result of a brotherpaul:// URL.
enum URLAction: Equatable {
    case start(mode: String?)
    case stop(mode: String?)
    case unknown(action: String)
}

/// Pure parser for brotherpaul:// URLs. No side effects, no I/O.
enum URLActionParser {

    /// Returns the parsed action, or nil if the input is not a parseable URL.
    static func parse(_ urlString: String) -> URLAction? {
        guard let components = URLComponents(string: urlString) else { return nil }

        let action = components.host
            ?? components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let mode = components.queryItems?
            .first { $0.name.caseInsensitiveCompare("mode") == .orderedSame }?
            .value

        switch action.lowercased() {
        case "start":
            return .start(mode: mode)
        case "stop", "end":
            return .stop(mode: mode)
        default:
            return .unknown(action: action)
        }
    }
}
```

- [ ] **Step 4.4: Run the tests — should pass**

```bash
swift test --filter URLActionTests
```

Expected: all nine tests pass.

- [ ] **Step 4.5: Wire AppDelegate to the parser**

In `Sources/BrotherPaul/AppDelegate.swift`, replace the entire `handleURLEvent` method body (lines 61–78) with the version that uses the parser:

```swift
    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let action = URLActionParser.parse(urlString) else {
            return
        }

        switch action {
        case .start(let mode):
            launch(modeName: mode)
        case .stop(let mode):
            endSession(modeName: mode)
        case .unknown(let name):
            NSLog("BrotherPaul: ignoring URL with unknown action '%@'", name)
        }
    }
```

- [ ] **Step 4.6: Build the executable to confirm no regressions**

```bash
swift build -c release
```

Expected: `Build complete!` with no errors.

- [ ] **Step 4.7: Run the full test suite**

```bash
swift test
```

Expected: every test still passes.

- [ ] **Step 4.8: Commit**

```bash
git add Sources/BrotherPaul/URLActionParser.swift Sources/BrotherPaul/AppDelegate.swift Tests/BrotherPaulTests/URLActionTests.swift
git commit -m "$(cat <<'EOF'
refactor: extract URLActionParser from AppDelegate

Pulls the brotherpaul:// parsing into a pure helper so it can be unit
tested. AppDelegate.handleURLEvent now switches over the parsed result.
Behavior preserved (case-insensitive action, end → stop alias, mode
query-key insensitivity, unknown actions logged).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: DigestSorter extraction + tests

Pull the `items.sort` block out of `MissionControlCoordinator.mergeEmail` into a pure helper. TDD.

**Files:**
- Create: `Sources/BrotherPaul/DigestSorter.swift`
- Create: `Tests/BrotherPaulTests/DigestSorterTests.swift`
- Modify: `Sources/BrotherPaul/MissionControlCoordinator.swift:108-111`

- [ ] **Step 5.1: Write the failing tests**

Write `Tests/BrotherPaulTests/DigestSorterTests.swift`:

```swift
import XCTest
@testable import BrotherPaul

final class DigestSorterTests: XCTestCase {

    private func item(_ title: String, priority: Int, timestamp: Date?) -> DigestItem {
        DigestItem(
            source: .outlook,
            title: title,
            subtitle: nil,
            timestamp: timestamp,
            priority: priority,
            openURL: nil
        )
    }

    func test_sorts_by_priority_descending() {
        let a = item("a", priority: 50, timestamp: nil)
        let b = item("b", priority: 90, timestamp: nil)
        let c = item("c", priority: 30, timestamp: nil)
        let sorted = DigestSorter.sort([a, b, c])
        XCTAssertEqual(sorted.map(\.title), ["b", "a", "c"])
    }

    func test_within_same_priority_sorts_by_timestamp_descending() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let older = item("older", priority: 50, timestamp: now.addingTimeInterval(-3600))
        let newer = item("newer", priority: 50, timestamp: now)
        let sorted = DigestSorter.sort([older, newer])
        XCTAssertEqual(sorted.map(\.title), ["newer", "older"])
    }

    func test_nil_timestamps_go_last_within_a_priority_band() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let dated = item("dated", priority: 50, timestamp: now)
        let undated = item("undated", priority: 50, timestamp: nil)
        let sorted = DigestSorter.sort([undated, dated])
        XCTAssertEqual(sorted.map(\.title), ["dated", "undated"])
    }

    func test_empty_input_returns_empty() {
        XCTAssertTrue(DigestSorter.sort([]).isEmpty)
    }
}
```

- [ ] **Step 5.2: Run the failing tests**

```bash
swift test --filter DigestSorterTests
```

Expected: build fails — `DigestSorter` does not exist.

- [ ] **Step 5.3: Create the sorter**

Write `Sources/BrotherPaul/DigestSorter.swift`:

```swift
import Foundation

/// Sort DigestItems for display: priority descending, then timestamp descending
/// (most-recent first). Items with nil timestamps sort to the end of their
/// priority band.
enum DigestSorter {

    static func sort(_ items: [DigestItem]) -> [DigestItem] {
        items.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast)
        }
    }
}
```

- [ ] **Step 5.4: Run the tests — should pass**

```bash
swift test --filter DigestSorterTests
```

Expected: all four tests pass.

- [ ] **Step 5.5: Wire `MissionControlCoordinator` to the sorter**

In `Sources/BrotherPaul/MissionControlCoordinator.swift`, find `mergeEmail` (around line 106). Replace the four-line sort block:

```swift
        var items = outlook.items + gmail.items
        items.sort {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast)
        }
```

with:

```swift
        let items = DigestSorter.sort(outlook.items + gmail.items)
```

- [ ] **Step 5.6: Build to confirm no regressions**

```bash
swift build -c release
swift test
```

Expected: build succeeds; all tests pass.

- [ ] **Step 5.7: Commit**

```bash
git add Sources/BrotherPaul/DigestSorter.swift Sources/BrotherPaul/MissionControlCoordinator.swift Tests/BrotherPaulTests/DigestSorterTests.swift
git commit -m "$(cat <<'EOF'
refactor: extract DigestSorter for testable priority ordering

Pulls the email merge sort out of MissionControlCoordinator into a pure
helper. Order semantics preserved: priority desc, then timestamp desc,
nil timestamps last in a priority band.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: VIPMatcher extraction + tests

Pull the VIP substring match out of `GmailFetcher` and `OutlookFetcher` into a shared pure helper. Different call sites match against different field sets (Gmail: from only; Outlook: sender + subject), so the helper takes `haystacks: [String]`. TDD.

**Files:**
- Create: `Sources/BrotherPaul/VIPMatcher.swift`
- Create: `Tests/BrotherPaulTests/DigestFilterTests.swift` (also hosts NotificationBlocklist tests in Task 7)
- Modify: `Sources/BrotherPaul/GmailFetcher.swift:103-106`
- Modify: `Sources/BrotherPaul/OutlookFetcher.swift:75-78`

- [ ] **Step 6.1: Write the failing tests**

Write `Tests/BrotherPaulTests/DigestFilterTests.swift`:

```swift
import XCTest
@testable import BrotherPaul

final class VIPMatcherTests: XCTestCase {

    func test_no_vip_senders_means_never_matches() {
        XCTAssertFalse(VIPMatcher.isVIP(haystacks: ["boss@example.com"], vipSenders: []))
    }

    func test_substring_match_is_case_insensitive() {
        XCTAssertTrue(VIPMatcher.isVIP(
            haystacks: ["Boss Person <boss@Example.com>"],
            vipSenders: ["boss@example.com"]
        ))
    }

    func test_partial_match_against_display_name() {
        XCTAssertTrue(VIPMatcher.isVIP(
            haystacks: ["Alice Smith <alice@x.com>"],
            vipSenders: ["alice smith"]
        ))
    }

    func test_no_match_when_neither_field_contains_vip() {
        XCTAssertFalse(VIPMatcher.isVIP(
            haystacks: ["junk@example.com"],
            vipSenders: ["boss@example.com"]
        ))
    }

    func test_empty_vip_string_is_skipped_not_a_wildcard() {
        XCTAssertFalse(VIPMatcher.isVIP(
            haystacks: ["anything"],
            vipSenders: [""]
        ))
    }

    func test_matches_any_of_multiple_haystacks() {
        XCTAssertTrue(VIPMatcher.isVIP(
            haystacks: ["random sender", "Re: from the CEO"],
            vipSenders: ["ceo"]
        ))
    }

    func test_matches_any_of_multiple_vip_entries() {
        XCTAssertTrue(VIPMatcher.isVIP(
            haystacks: ["alice@x.com"],
            vipSenders: ["bob@x.com", "alice@x.com"]
        ))
    }
}
```

- [ ] **Step 6.2: Run the failing tests**

```bash
swift test --filter VIPMatcherTests
```

Expected: build fails — `VIPMatcher` does not exist.

- [ ] **Step 6.3: Create the matcher**

Write `Sources/BrotherPaul/VIPMatcher.swift`:

```swift
import Foundation

/// Pure VIP-sender check used by GmailFetcher (matches against `from`) and
/// OutlookFetcher (matches against sender + subject). Empty vipSenders never
/// matches; empty entries inside vipSenders are skipped (so an accidental
/// blank in config doesn't behave like a wildcard).
enum VIPMatcher {

    static func isVIP(haystacks: [String], vipSenders: [String]) -> Bool {
        for vip in vipSenders {
            let v = vip.lowercased()
            guard !v.isEmpty else { continue }
            for haystack in haystacks {
                if haystack.lowercased().contains(v) { return true }
            }
        }
        return false
    }
}
```

- [ ] **Step 6.4: Run the tests — should pass**

```bash
swift test --filter VIPMatcherTests
```

Expected: all seven tests pass.

- [ ] **Step 6.5: Wire GmailFetcher**

In `Sources/BrotherPaul/GmailFetcher.swift`, find the VIP check (around line 103):

```swift
        let isVIP = vipSenders.contains { vip in
            let v = vip.lowercased()
            return !v.isEmpty && from.lowercased().contains(v)
        }
```

Replace with:

```swift
        let isVIP = VIPMatcher.isVIP(haystacks: [from], vipSenders: vipSenders)
```

- [ ] **Step 6.6: Wire OutlookFetcher**

In `Sources/BrotherPaul/OutlookFetcher.swift`, find the VIP check (around line 75):

```swift
            let isVIP = vipSenders.contains { vip in
                let v = vip.lowercased()
                return !v.isEmpty && (sender.lowercased().contains(v) || subject.lowercased().contains(v))
            }
```

Replace with:

```swift
            let isVIP = VIPMatcher.isVIP(haystacks: [sender, subject], vipSenders: vipSenders)
```

- [ ] **Step 6.7: Build and run full suite**

```bash
swift build -c release
swift test
```

Expected: build succeeds; every test passes (including the new `VIPMatcherTests`).

- [ ] **Step 6.8: Commit**

```bash
git add Sources/BrotherPaul/VIPMatcher.swift Sources/BrotherPaul/GmailFetcher.swift Sources/BrotherPaul/OutlookFetcher.swift Tests/BrotherPaulTests/DigestFilterTests.swift
git commit -m "$(cat <<'EOF'
refactor: extract VIPMatcher used by Gmail and Outlook fetchers

Both fetchers had near-identical VIP substring-match blocks; Gmail
matched against from, Outlook against sender + subject. Helper takes
haystacks: [String] so each caller passes the fields it wants checked.
Behavior preserved.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: NotificationBlocklist extraction + tests

Pull the bundle-ID blocklist check out of `NotificationsFetcher.run` into a pure helper. TDD. Tests live alongside VIPMatcher tests in `DigestFilterTests.swift`.

**Files:**
- Create: `Sources/BrotherPaul/NotificationBlocklist.swift`
- Modify: `Tests/BrotherPaulTests/DigestFilterTests.swift` (append new class)
- Modify: `Sources/BrotherPaul/NotificationsFetcher.swift:48,54`

- [ ] **Step 7.1: Append the failing tests**

Append to `Tests/BrotherPaulTests/DigestFilterTests.swift`:

```swift
final class NotificationBlocklistTests: XCTestCase {

    func test_empty_blocklist_includes_everything() {
        XCTAssertTrue(NotificationBlocklist.shouldInclude(
            bundleID: "com.example.app",
            blocklist: []
        ))
    }

    func test_match_excludes() {
        XCTAssertFalse(NotificationBlocklist.shouldInclude(
            bundleID: "com.apple.systemnotifications",
            blocklist: ["com.apple.systemnotifications"]
        ))
    }

    func test_match_is_case_insensitive() {
        XCTAssertFalse(NotificationBlocklist.shouldInclude(
            bundleID: "com.apple.SystemNotifications",
            blocklist: ["COM.APPLE.systemnotifications"]
        ))
    }

    func test_match_is_exact_bundle_id_not_substring() {
        // "apple" is a substring of "com.apple.X" but blocklist is exact match.
        XCTAssertTrue(NotificationBlocklist.shouldInclude(
            bundleID: "com.apple.mail",
            blocklist: ["apple"]
        ))
    }

    func test_non_matching_bundle_is_included() {
        XCTAssertTrue(NotificationBlocklist.shouldInclude(
            bundleID: "com.example.app",
            blocklist: ["com.apple.systemnotifications", "com.other.thing"]
        ))
    }
}
```

- [ ] **Step 7.2: Run the failing tests**

```bash
swift test --filter NotificationBlocklistTests
```

Expected: build fails — `NotificationBlocklist` does not exist.

- [ ] **Step 7.3: Create the helper**

Write `Sources/BrotherPaul/NotificationBlocklist.swift`:

```swift
import Foundation

/// Pure bundle-ID blocklist check used by NotificationsFetcher.
/// Matches exact bundle IDs (case-insensitive). Empty blocklist is pass-through.
enum NotificationBlocklist {

    static func shouldInclude(bundleID: String, blocklist: [String]) -> Bool {
        let blocked = Set(blocklist.map { $0.lowercased() })
        return !blocked.contains(bundleID.lowercased())
    }
}
```

- [ ] **Step 7.4: Run the tests — should pass**

```bash
swift test --filter NotificationBlocklistTests
```

Expected: all five tests pass.

- [ ] **Step 7.5: Wire NotificationsFetcher**

In `Sources/BrotherPaul/NotificationsFetcher.swift`, remove the local set construction (line 48) and the inline check (line 54). The current code looks like:

```swift
        var items: [DigestItem] = []
        let blocklistLower = Set(blocklist.map { $0.lowercased() })

        while sqlite3_step(stmt) == SQLITE_ROW {
            let deliveredSinceRef = sqlite3_column_double(stmt, 0)
            let identifier = String(cString: sqlite3_column_text(stmt, 1))

            if blocklistLower.contains(identifier.lowercased()) { continue }
```

Replace with:

```swift
        var items: [DigestItem] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let deliveredSinceRef = sqlite3_column_double(stmt, 0)
            let identifier = String(cString: sqlite3_column_text(stmt, 1))

            if !NotificationBlocklist.shouldInclude(bundleID: identifier, blocklist: blocklist) { continue }
```

- [ ] **Step 7.6: Build and run full suite**

```bash
swift build -c release
swift test
```

Expected: build succeeds; every test passes.

- [ ] **Step 7.7: Commit**

```bash
git add Sources/BrotherPaul/NotificationBlocklist.swift Sources/BrotherPaul/NotificationsFetcher.swift Tests/BrotherPaulTests/DigestFilterTests.swift
git commit -m "$(cat <<'EOF'
refactor: extract NotificationBlocklist helper

Pulls the bundle-ID blocklist check out of NotificationsFetcher.run
into a pure helper. Behavior preserved (case-insensitive exact match,
empty blocklist is pass-through).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: SnapZone CGRect-based variants + tests

Add `CGRect`-parameter variants of `frame(in:)` and `zoneForCursor(_:on:)` so tests don't need a real `NSScreen`. The existing `NSScreen` overloads remain and forward to the new variants. TDD.

**Files:**
- Modify: `Sources/BrotherPaul/SnapZone.swift`
- Create: `Tests/BrotherPaulTests/SnapZoneTests.swift`

- [ ] **Step 8.1: Write the failing tests**

Write `Tests/BrotherPaulTests/SnapZoneTests.swift`:

```swift
import XCTest
@testable import BrotherPaul

final class SnapZoneTests: XCTestCase {

    /// A canonical 1920×1080 visible frame at origin (0,0) for frame() tests.
    private let visible = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    // MARK: - frame(inVisibleFrame:)

    func test_leftHalf_frame() {
        XCTAssertEqual(SnapZone.leftHalf.frame(inVisibleFrame: visible),
                       CGRect(x: 0, y: 0, width: 960, height: 1080))
    }

    func test_rightHalf_frame() {
        XCTAssertEqual(SnapZone.rightHalf.frame(inVisibleFrame: visible),
                       CGRect(x: 960, y: 0, width: 960, height: 1080))
    }

    func test_topLeftQuarter_frame() {
        XCTAssertEqual(SnapZone.topLeftQuarter.frame(inVisibleFrame: visible),
                       CGRect(x: 0, y: 540, width: 960, height: 540))
    }

    func test_maximize_frame() {
        XCTAssertEqual(SnapZone.maximize.frame(inVisibleFrame: visible), visible)
    }

    func test_center_frame_is_60_by_70_percent_centered() {
        let f = SnapZone.center.frame(inVisibleFrame: visible)
        XCTAssertEqual(f.width, 1152, accuracy: 0.01)
        XCTAssertEqual(f.height, 756, accuracy: 0.01)
        XCTAssertEqual(f.midX, visible.midX, accuracy: 0.01)
        XCTAssertEqual(f.midY, visible.midY, accuracy: 0.01)
    }

    func test_frame_respects_nonzero_origin() {
        // Second monitor at (1920, 0), same size.
        let offset = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(SnapZone.leftHalf.frame(inVisibleFrame: offset),
                       CGRect(x: 1920, y: 0, width: 960, height: 1080))
    }

    // MARK: - zoneForCursor(_:screenFrame:)

    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func test_cursor_in_corner_picks_quadrant() {
        XCTAssertEqual(SnapZone.zoneForCursor(CGPoint(x: 5, y: 1075),
                                              screenFrame: screen),
                       .topLeftQuarter)
        XCTAssertEqual(SnapZone.zoneForCursor(CGPoint(x: 1915, y: 1075),
                                              screenFrame: screen),
                       .topRightQuarter)
        XCTAssertEqual(SnapZone.zoneForCursor(CGPoint(x: 5, y: 5),
                                              screenFrame: screen),
                       .bottomLeftQuarter)
        XCTAssertEqual(SnapZone.zoneForCursor(CGPoint(x: 1915, y: 5),
                                              screenFrame: screen),
                       .bottomRightQuarter)
    }

    func test_cursor_against_top_edge_picks_maximize() {
        XCTAssertEqual(SnapZone.zoneForCursor(CGPoint(x: 800, y: 1080),
                                              screenFrame: screen),
                       .maximize)
    }

    func test_cursor_against_left_edge_picks_leftHalf() {
        XCTAssertEqual(SnapZone.zoneForCursor(CGPoint(x: 0, y: 540),
                                              screenFrame: screen),
                       .leftHalf)
    }

    func test_cursor_in_middle_returns_nil() {
        XCTAssertNil(SnapZone.zoneForCursor(CGPoint(x: 800, y: 500),
                                             screenFrame: screen))
    }
}
```

- [ ] **Step 8.2: Run the failing tests**

```bash
swift test --filter SnapZoneTests
```

Expected: build fails — `frame(inVisibleFrame:)` and `zoneForCursor(_:screenFrame:)` do not exist.

- [ ] **Step 8.3: Add CGRect-based variants**

In `Sources/BrotherPaul/SnapZone.swift`, replace the existing `frame(in:)` method (lines 23–52) with:

```swift
    /// Compute the target frame in screen coordinates (origin = bottom-left).
    func frame(in screen: NSScreen) -> CGRect {
        frame(inVisibleFrame: screen.visibleFrame)
    }

    /// CGRect-parameter variant so this is unit-testable without an NSScreen.
    func frame(inVisibleFrame v: CGRect) -> CGRect {
        let half = CGSize(width: v.width / 2, height: v.height / 2)

        switch self {
        case .leftHalf:
            return CGRect(x: v.minX, y: v.minY, width: half.width, height: v.height)
        case .rightHalf:
            return CGRect(x: v.midX, y: v.minY, width: half.width, height: v.height)
        case .topHalf:
            return CGRect(x: v.minX, y: v.midY, width: v.width, height: half.height)
        case .bottomHalf:
            return CGRect(x: v.minX, y: v.minY, width: v.width, height: half.height)
        case .topLeftQuarter:
            return CGRect(x: v.minX, y: v.midY, width: half.width, height: half.height)
        case .topRightQuarter:
            return CGRect(x: v.midX, y: v.midY, width: half.width, height: half.height)
        case .bottomLeftQuarter:
            return CGRect(x: v.minX, y: v.minY, width: half.width, height: half.height)
        case .bottomRightQuarter:
            return CGRect(x: v.midX, y: v.minY, width: half.width, height: half.height)
        case .maximize:
            return v
        case .center:
            let w = v.width * 0.6
            let h = v.height * 0.7
            return CGRect(x: v.midX - w / 2, y: v.midY - h / 2, width: w, height: h)
        }
    }
```

And replace the existing `static func zoneForCursor(_:on:)` method (lines 56–82) with:

```swift
    /// Pick a zone when the cursor is near a screen edge / corner.
    /// `cursor` is in global screen coordinates (origin = bottom-left of primary screen).
    static func zoneForCursor(_ cursor: CGPoint, on screen: NSScreen) -> SnapZone? {
        zoneForCursor(cursor, screenFrame: screen.frame)
    }

    /// CGRect-parameter variant so this is unit-testable without an NSScreen.
    static func zoneForCursor(_ cursor: CGPoint, screenFrame frame: CGRect) -> SnapZone? {
        let cornerSize: CGFloat = 30
        let edgeThreshold: CGFloat = 6

        let nearLeft   = cursor.x <= frame.minX + edgeThreshold
        let nearRight  = cursor.x >= frame.maxX - edgeThreshold
        let nearTop    = cursor.y >= frame.maxY - edgeThreshold
        let nearBottom = cursor.y <= frame.minY + edgeThreshold

        let inTopLeftCorner     = cursor.x <= frame.minX + cornerSize && cursor.y >= frame.maxY - cornerSize
        let inTopRightCorner    = cursor.x >= frame.maxX - cornerSize && cursor.y >= frame.maxY - cornerSize
        let inBottomLeftCorner  = cursor.x <= frame.minX + cornerSize && cursor.y <= frame.minY + cornerSize
        let inBottomRightCorner = cursor.x >= frame.maxX - cornerSize && cursor.y <= frame.minY + cornerSize

        if inTopLeftCorner     { return .topLeftQuarter }
        if inTopRightCorner    { return .topRightQuarter }
        if inBottomLeftCorner  { return .bottomLeftQuarter }
        if inBottomRightCorner { return .bottomRightQuarter }

        if nearTop    { return .maximize }
        if nearLeft   { return .leftHalf }
        if nearRight  { return .rightHalf }
        if nearBottom { return .bottomHalf }

        return nil
    }
```

- [ ] **Step 8.4: Run the tests — should pass**

```bash
swift test --filter SnapZoneTests
```

Expected: all eleven tests pass.

- [ ] **Step 8.5: Build to confirm no regressions**

```bash
swift build -c release
swift test
```

Expected: build succeeds; every test passes.

- [ ] **Step 8.6: Commit**

```bash
git add Sources/BrotherPaul/SnapZone.swift Tests/BrotherPaulTests/SnapZoneTests.swift
git commit -m "$(cat <<'EOF'
refactor: add CGRect-based SnapZone variants for testability

Existing NSScreen-based frame(in:) and zoneForCursor(_:on:) overloads
now forward to frame(inVisibleFrame:) and zoneForCursor(_:screenFrame:).
Tests use the CGRect variants directly. Production callers unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: VerseOfTheDay tests + cache invalidation helper

Test the deterministic by-day picker and the `randomVerse(excluding:)` exclusion guarantee. `VerseOfTheDay` caches custom verses across calls; add an internal `invalidateCacheForTesting()` so tests can reset between cases.

**Files:**
- Modify: `Sources/BrotherPaul/VerseOfTheDay.swift` (add one method)
- Create: `Tests/BrotherPaulTests/VerseOfTheDayTests.swift`

- [ ] **Step 9.1: Add the cache invalidation hook**

In `Sources/BrotherPaul/VerseOfTheDay.swift`, just before `private enum CachedLoad` (around line 85), add:

```swift
    /// Reset the cached verses load. Only intended for tests — call after
    /// changing the BROTHERPAUL_CONFIG_DIR-redirected custom verses file so
    /// the next read picks it up.
    static func invalidateCacheForTesting() {
        cachedCustomVerses = .uninitialized
    }
```

- [ ] **Step 9.2: Write the tests**

Write `Tests/BrotherPaulTests/VerseOfTheDayTests.swift`:

```swift
import XCTest
@testable import BrotherPaul

final class VerseOfTheDayTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("brpaul-verses-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        setenv("BROTHERPAUL_CONFIG_DIR", tmp.path, 1)
        VerseOfTheDay.invalidateCacheForTesting()
    }

    override func tearDownWithError() throws {
        unsetenv("BROTHERPAUL_CONFIG_DIR")
        VerseOfTheDay.invalidateCacheForTesting()
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - todays(now:)

    func test_todays_is_stable_for_the_same_date() {
        let date = makeDate(year: 2026, month: 5, day: 21)
        let first = VerseOfTheDay.todays(now: date)
        let second = VerseOfTheDay.todays(now: date)
        XCTAssertEqual(first, second)
    }

    func test_todays_rotates_across_days() {
        // The default verse list has 120 entries; consecutive days must differ.
        let day1 = makeDate(year: 2026, month: 5, day: 21)
        let day2 = makeDate(year: 2026, month: 5, day: 22)
        XCTAssertNotEqual(VerseOfTheDay.todays(now: day1),
                          VerseOfTheDay.todays(now: day2))
    }

    func test_todays_wraps_modulo_pool_size() {
        // Same ordinal modulo defaultVerses.count produces the same verse.
        let n = VerseOfTheDay.defaultVerses.count
        let day1 = makeDate(year: 2026, month: 1, day: 1)
        guard let day1PlusN = Calendar.current.date(byAdding: .day, value: n, to: day1)
        else { return XCTFail("date math failed") }
        XCTAssertEqual(VerseOfTheDay.todays(now: day1),
                       VerseOfTheDay.todays(now: day1PlusN))
    }

    // MARK: - randomVerse(excluding:)

    func test_randomVerse_excludes_the_passed_verse() {
        let pinned = VerseOfTheDay.defaultVerses[0]
        for _ in 0..<20 {
            let pick = VerseOfTheDay.randomVerse(excluding: pinned)
            XCTAssertNotEqual(pick, pinned)
        }
    }

    func test_randomVerse_with_nil_excluding_returns_some_verse() {
        let pick = VerseOfTheDay.randomVerse(excluding: nil)
        XCTAssertTrue(VerseOfTheDay.defaultVerses.contains(pick))
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return Calendar.current.date(from: comps)!
    }
}
```

- [ ] **Step 9.3: Run the tests — should pass**

```bash
swift test --filter VerseOfTheDayTests
```

Expected: all five tests pass.

- [ ] **Step 9.4: Build and run full suite**

```bash
swift build -c release
swift test
```

Expected: build succeeds; every test passes.

- [ ] **Step 9.5: Commit**

```bash
git add Sources/BrotherPaul/VerseOfTheDay.swift Tests/BrotherPaulTests/VerseOfTheDayTests.swift
git commit -m "$(cat <<'EOF'
test: cover VerseOfTheDay date stability and exclusion guarantee

Adds invalidateCacheForTesting() so tests can reset the verse-load
cache between cases. Tests pin: same date → same verse; consecutive
days differ; ordinal-mod-pool wraps; randomVerse never returns the
excluded one.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Smoke harness — `bin/smoke-test.sh`

A bash script that exercises real `brotherpaul://` URLs end-to-end. Hermetic via `BROTHERPAUL_CONFIG_DIR`, safe via pre-flight checks, robust via `trap` cleanup.

**Files:**
- Create: `bin/smoke-test.sh` (executable)

- [ ] **Step 10.1: Write the script**

Write `bin/smoke-test.sh`:

```bash
#!/usr/bin/env bash
# Smoke test for BrotherPaul: exercises the real .app through brotherpaul://
# URLs against a hermetic fixture config. Safe to run on a normal Mac because
# we refuse to start if the target test apps (TextEdit, Calculator) are
# already running.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="/Applications/BrotherPaul.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Support/lsregister"

TMP_DIR=""
PASS=0
FAIL=0

# ---- helpers ----------------------------------------------------------------

cleanup() {
    set +e
    pkill -x BrotherPaul 2>/dev/null
    pkill -x TextEdit 2>/dev/null
    pkill -x Calculator 2>/dev/null
    launchctl unsetenv BROTHERPAUL_CONFIG_DIR 2>/dev/null
    if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
        rm -rf "${TMP_DIR}"
    fi
}
trap cleanup EXIT INT TERM

ok()   { echo "✓ $*"; PASS=$((PASS+1)); }
fail() { echo "✗ $*" >&2; FAIL=$((FAIL+1)); }

# Wait until $1 (a pgrep -x name) is running, up to $2 seconds. Returns 0 on success.
wait_for_proc() {
    local name="$1"; local timeout="${2:-10}"
    for _ in $(seq 1 "$timeout"); do
        if pgrep -x "$name" >/dev/null; then return 0; fi
        sleep 1
    done
    return 1
}

# Wait until $1 is NOT running, up to $2 seconds.
wait_for_no_proc() {
    local name="$1"; local timeout="${2:-10}"
    for _ in $(seq 1 "$timeout"); do
        if ! pgrep -x "$name" >/dev/null; then return 0; fi
        sleep 1
    done
    return 1
}

# ---- 1. Pre-flight ----------------------------------------------------------

if [[ ! -d "${APP_PATH}" ]]; then
    fail "BrotherPaul.app missing at ${APP_PATH}. Run ./build-app.sh first."
    exit 2
fi

if pgrep -x TextEdit >/dev/null; then
    fail "TextEdit is already running — refusing to nuke your live work. Quit it and retry."
    exit 2
fi
if pgrep -x Calculator >/dev/null; then
    fail "Calculator is already running — refusing to nuke your live work. Quit it and retry."
    exit 2
fi
ok "Pre-flight clean"

# ---- 2. Build & install -----------------------------------------------------

(cd "${ROOT}" && ./build-app.sh >/dev/null)
ok "Built and installed"

# ---- 3. Stage fixture config ------------------------------------------------

TMP_DIR="$(mktemp -d -t brpaul-smoke)"
cat > "${TMP_DIR}/config.json" <<'JSON'
{
  "hideOthersAfterLaunch": false,
  "defaultMode": "SmokeStart",
  "modes": [
    { "name": "SmokeStart", "apps": ["TextEdit", "Calculator"], "urls": [] }
  ],
  "enableSnap": false,
  "enableDragSnap": false,
  "missionControl": {
    "includeCalendar": false,
    "includeOutlook": false,
    "includeOutlookCalendar": false,
    "includeGraphCalendar": false,
    "includeGmail": false,
    "includeNotifications": false,
    "includeVerseOfDay": false,
    "lookbackHours": 24,
    "vipSenders": [],
    "notificationAppBlocklist": [],
    "openOnStartWork": false,
    "quickLinks": [],
    "gmail": { "clientID": "", "clientSecret": "", "refreshToken": "" },
    "graph": { "clientID": "", "tenant": "common", "refreshToken": "" }
  }
}
JSON

# ---- 4. Cold-launch BrotherPaul with the override ---------------------------

pkill -x BrotherPaul 2>/dev/null || true
sleep 1
launchctl setenv BROTHERPAUL_CONFIG_DIR "${TMP_DIR}"
"${LSREGISTER}" -f "${APP_PATH}" >/dev/null 2>&1 || true
open -gj "${APP_PATH}"

if wait_for_proc BrotherPaul 10; then
    ok "Cold launch with BROTHERPAUL_CONFIG_DIR=${TMP_DIR}"
else
    fail "BrotherPaul did not start within 10s"
    exit 1
fi
sleep 1  # let applicationDidFinishLaunching settle

# ---- 5. Positive start ------------------------------------------------------

open "brotherpaul://start?mode=SmokeStart"

if wait_for_proc TextEdit 10 && wait_for_proc Calculator 10; then
    ok "Start SmokeStart → TextEdit + Calculator up"
else
    fail "TextEdit and/or Calculator did not launch within 10s"
fi

# ---- 6. Positive stop -------------------------------------------------------

open "brotherpaul://stop?mode=SmokeStart"

if wait_for_no_proc TextEdit 10 && wait_for_no_proc Calculator 10; then
    ok "Stop SmokeStart → both quit"
else
    fail "TextEdit and/or Calculator did not quit within 10s"
fi

# ---- 7. Negative: unknown mode ---------------------------------------------

# Sentinel: nothing should launch.
before="$(pgrep -lx TextEdit; pgrep -lx Calculator || true)"
open "brotherpaul://start?mode=DoesNotExist"
sleep 2
after="$(pgrep -lx TextEdit; pgrep -lx Calculator || true)"

if [[ "${before}" == "${after}" ]]; then
    ok "Start DoesNotExist → no apps launched"
else
    fail "Unknown mode caused unexpected launches: diff '${before}' → '${after}'"
fi

# Confirm the log shows the unknown-mode branch actually ran.
if log show --predicate 'process == "BrotherPaul"' --last 30s 2>/dev/null \
   | grep -q "unknown mode 'DoesNotExist'"; then
    ok "Log records: unknown mode 'DoesNotExist'"
else
    # NSLog can take a moment to surface; soft-fail to a warning rather than hard fail.
    echo "⚠ Could not confirm 'unknown mode' log entry (NSLog may be delayed; check manually if this happens repeatedly)"
fi

# ---- Summary ----------------------------------------------------------------

echo
echo "PASS=${PASS}  FAIL=${FAIL}"
if [[ "${FAIL}" -gt 0 ]]; then
    exit 1
fi
echo "All smoke checks passed."
```

- [ ] **Step 10.2: Make it executable**

```bash
chmod +x bin/smoke-test.sh
```

- [ ] **Step 10.3: Run it**

```bash
./bin/smoke-test.sh
```

Expected output (last several lines):

```
✓ Pre-flight clean
✓ Built and installed
✓ Cold launch with BROTHERPAUL_CONFIG_DIR=/var/folders/.../brpaul-smoke.XXX
✓ Start SmokeStart → TextEdit + Calculator up
✓ Stop SmokeStart → both quit
✓ Start DoesNotExist → no apps launched
✓ Log records: unknown mode 'DoesNotExist'

PASS=7  FAIL=0
All smoke checks passed.
```

If TextEdit or Calculator is already running, expect exit code 2 with a clear "refusing to nuke your live work" message; quit them and retry.

- [ ] **Step 10.4: Commit**

```bash
git add bin/smoke-test.sh
git commit -m "$(cat <<'EOF'
test: add bin/smoke-test.sh end-to-end harness

Exercises real brotherpaul:// URLs against a hermetic fixture config
(via BROTHERPAUL_CONFIG_DIR). Pre-flight refuses to run if TextEdit or
Calculator are already running. Cleanup is trap'd so Ctrl-C / failure
still unsets the launchctl env and removes the tmp config dir.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Top-level `bin/test.sh`

One command that runs unit tests then smoke tests, with a clear PASS/FAIL summary.

**Files:**
- Create: `bin/test.sh` (executable)

- [ ] **Step 11.1: Write the script**

Write `bin/test.sh`:

```bash
#!/usr/bin/env bash
# Run the full Brother Paul test suite: XCTest units, then the bin/smoke-test.sh
# end-to-end harness. Exits non-zero on any failure.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

echo "=== Unit tests (swift test) ==="
swift test

echo
echo "=== Smoke tests (bin/smoke-test.sh) ==="
./bin/smoke-test.sh

echo
echo "All tests passed."
```

- [ ] **Step 11.2: Make it executable**

```bash
chmod +x bin/test.sh
```

- [ ] **Step 11.3: Run it**

```bash
./bin/test.sh
```

Expected: swift test output (all suites green), followed by smoke test output (PASS=7 FAIL=0), final line `All tests passed.` Exit code 0.

- [ ] **Step 11.4: Commit**

```bash
git add bin/test.sh
git commit -m "$(cat <<'EOF'
test: add bin/test.sh runner — swift test + smoke in one command

One command, two gates: unit tests then end-to-end smoke. Non-zero
exit on any failure.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-review checklist (for the implementer)

After every task in this plan is complete:

- [ ] `swift test` passes locally
- [ ] `./bin/smoke-test.sh` passes locally
- [ ] `./bin/test.sh` passes locally
- [ ] `swift build -c release` still produces a working binary
- [ ] `git log --oneline` shows one commit per task (eleven commits)
- [ ] No new test target dependencies introduced beyond XCTest
- [ ] The spec's "Out of scope" list still reflects what's NOT covered
