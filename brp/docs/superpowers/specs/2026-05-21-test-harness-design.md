# Brother Paul Test Harness — Design

**Date:** 2026-05-21
**Status:** Approved, ready for implementation plan

## Goal

Give Brother Paul a regression safety net that covers both the pure logic
(parsing, models, geometry) and the real user-visible flow that broke this
week — Siri / URL → cold-launch → apps actually launching.

## Architecture

Two pieces, runnable separately or together via `bin/test.sh`:

1. **Unit tests** — XCTest suite under `Tests/BrotherPaulTests/`. Pure logic
   only. Runs via `swift test` in <2s. No macOS permissions, no app launches,
   no network.

2. **Smoke harness** — `bin/smoke-test.sh`. Builds + installs the app, points
   it at a hermetic fixture config via `$BROTHERPAUL_CONFIG_DIR`, fires real
   `brotherpaul://` URLs, asserts TextEdit/Calculator launch and quit on cue.
   Runs in ~15s. Manual: invoked before shipping a build.

A top-level `bin/test.sh` runs both in sequence so "did everything pass?" is
one command.

## Unit test surface

Seven files, each focused on one module's pure logic. Each ≤150 lines.

| File | Coverage |
|---|---|
| `AppConfigTests.swift` | JSON decoding from realistic + minimal fixtures; default fallbacks for missing keys (`enableSnap`, `enableDragSnap`, `missionControl` block); `mode(named:)` case-insensitive lookup; unknown mode returns nil |
| `ConfigManagerTests.swift` | `bootstrap()` creates dir + writes default when missing; `reload()` round-trips a written config; `write()` is atomic. Per-test tmp dir via `BROTHERPAUL_CONFIG_DIR` |
| `URLActionTests.swift` | `brotherpaul://start`, `…/start?mode=Deep%20Work`, `…/stop`, `…/end` alias, mixed case, unknown action, malformed input, URL-decoded mode names with spaces |
| `SnapZoneTests.swift` | Frame computation for left-half / right-half / quadrants against canonical visible-frame `CGRect`s; `zoneForCursor` corner / edge detection on a synthetic screen rect |
| `VerseOfTheDayTests.swift` | `todays(now:)` is stable per date and rotates across days; `randomVerse(excluding:)` never returns the excluded verse; seed-version comparison gates re-seeding |
| `DigestSorterTests.swift` | `DigestSorter.sort(_:)` orders by priority desc, then by timestamp desc; ties stable; mixed nil timestamps go last |
| `DigestFilterTests.swift` | `VIPMatcher.isVIP(sender:vipSenders:)` — case-insensitive partial match, empty vipSenders never matches, whitespace handling. `NotificationBlocklist.shouldInclude(bundleID:blocklist:)` — case-insensitive exact-bundle-ID match, empty blocklist is pass-through |

Total: ~50–70 assertions.

## Code changes needed

Three small, surgical edits to make the existing code testable. All
non-behavioral for the running app.

### 1. Extract URL parser

Pull the parsing block out of `AppDelegate.handleURLEvent` into a new
`URLActionParser` (free enum + static `parse(_:)`).

```swift
enum URLAction: Equatable {
    case start(mode: String?)
    case stop(mode: String?)
    case unknown(action: String)
}

enum URLActionParser {
    static func parse(_ urlString: String) -> URLAction? {
        guard let components = URLComponents(string: urlString) else { return nil }
        let action = components.host ?? components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let mode = components.queryItems?.first { $0.name.caseInsensitiveCompare("mode") == .orderedSame }?.value
        switch action.lowercased() {
        case "start": return .start(mode: mode)
        case "stop", "end": return .stop(mode: mode)
        default: return .unknown(action: action)
        }
    }
}
```

`handleURLEvent` becomes a switch over the result. Pure, trivially testable.

### 2. `BROTHERPAUL_CONFIG_DIR` env-var override

In `ConfigManager.configDirectory`:

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

Used by both `ConfigManagerTests` and the smoke harness. Not documented as a
user-facing feature.

### 3. Source extractions for testability

Three small extractions of inline logic into pure helpers. Each is a 5–10 line
new file; the call sites change from inline expression to one-line helper
call. Behavior preserved exactly.

- **`DigestSorter`** — pull the `items.sort { ... }` block out of
  `MissionControlCoordinator` (around line 108) into
  `DigestSorter.sort(_ items:)`. Coordinator calls `items =
  DigestSorter.sort(items)`.
- **`VIPMatcher`** — pull the `vipSenders.contains { vip in ... }` block out
  of `GmailFetcher` (line 103) and `OutlookFetcher` into
  `VIPMatcher.isVIP(sender:vipSenders:)`. Both fetchers call the helper.
- **`NotificationBlocklist`** — pull the `blocklistLower.contains(...)`
  check out of `NotificationsFetcher.run` into
  `NotificationBlocklist.shouldInclude(bundleID:blocklist:)`. Fetcher calls
  the helper.
- **`SnapZone` CGRect variants** — add
  `frame(visibleScreenFrame: CGRect) -> CGRect` and
  `static func zoneForCursor(_ cursor: CGPoint, screenFrame: CGRect)
  -> SnapZone?`. The existing NSScreen-based methods become one-line
  wrappers that forward to the CGRect variants. Tests use the CGRect
  variants directly.
- **`VerseOfTheDay`** — add `internal static func invalidateCacheForTesting()`
  that resets `cachedCustomVerses = .uninitialized`. Tests call it in
  `tearDown`.

### 4. `Package.swift`: add test target

```swift
.testTarget(
    name: "BrotherPaulTests",
    dependencies: ["BrotherPaul"],
    path: "Tests/BrotherPaulTests"
)
```

Tests use `@testable import BrotherPaul`. SwiftPM has supported testing
executable targets since 5.7, so no library-split refactor needed.

## Smoke harness — `bin/smoke-test.sh`

Bash script. Exercises the real `.app` end-to-end through the URL handler —
the exact path that broke this week.

### Steps

1. **Pre-flight checks.** Refuse to run if TextEdit or Calculator is already
   running (don't want to quit your live work). Refuse if
   `/Applications/BrotherPaul.app` is missing.
2. **Build & install.** Calls `./build-app.sh` so we're testing the current
   source.
3. **Stage fixture.** `mktemp -d` → write `config.json` with two modes:
   - `SmokeStart` — apps: `TextEdit`, `Calculator`; `hideOthersAfterLaunch:
     false`; `missionControl.openOnStartWork: false`.
   - `SmokeMissing` — intentionally absent from `modes[]`, used for negative
     test.
4. **Set env.** `launchctl setenv BROTHERPAUL_CONFIG_DIR "$tmp"` so the
   cold-launched app inherits it.
5. **Cold launch.** `pkill -x BrotherPaul`, then `open -gj
   /Applications/BrotherPaul.app` (background, no activation). Wait until it
   shows up in `pgrep`.
6. **Positive start test.** `open "brotherpaul://start?mode=SmokeStart"`. Poll
   up to 10s for `pgrep -x TextEdit && pgrep -x Calculator`. Fail if either
   missing.
7. **Positive stop test.** `open "brotherpaul://stop?mode=SmokeStart"`. Poll
   up to 10s for both PIDs to disappear. Fail if either survives.
8. **Negative test.** `open "brotherpaul://start?mode=DoesNotExist"`. Sleep
   2s. Assert nothing new came up (`pgrep` diff before/after).
9. **Log assertion.** `log show --predicate 'process == "BrotherPaul"'
   --last 30s | grep "unknown mode 'DoesNotExist'"` — confirms the negative
   path actually ran the parser and rejected the mode, not silently skipped.
10. **Cleanup (in `trap`).** `pkill -x BrotherPaul`, `pkill -x TextEdit`,
    `pkill -x Calculator`, `launchctl unsetenv BROTHERPAUL_CONFIG_DIR`,
    `rm -rf "$tmp"`. Runs on success, failure, or Ctrl-C.
11. **Summary.** Print PASS/FAIL per step; exit non-zero on any fail.

### Sample output

```
✓ Pre-flight clean
✓ Built and installed
✓ Cold launch with BROTHERPAUL_CONFIG_DIR=/tmp/brpaul-smoke-XXX
✓ Start SmokeStart → TextEdit+Calculator up
✓ Stop SmokeStart → both quit
✓ Start DoesNotExist → no apps launched, "unknown mode" logged
All smoke checks passed.
```

## Error handling

**Smoke harness:**
- `set -euo pipefail` so any unchecked failure aborts cleanly.
- Pre-flight gates exit 2 with a clear message, no destructive action.
- Every cleanup step in a `trap` so Ctrl-C / mid-flight failure restores
  state.
- Polls have a hard timeout (10s); never spin forever.
- Each assertion prints expected vs. observed on failure.

**Unit tests:**
- `ConfigManagerTests` uses `setUp`/`tearDown` to create/destroy a per-test
  tmp dir and only set `BROTHERPAUL_CONFIG_DIR` inside the test process —
  never leaks to other tests or the real user config.
- Fixture JSONs live inline in the test files (no resource bundle plumbing)
  to keep them obviously correct at a glance.

## Entry points

```
swift test              # unit tests only — fast, CI-friendly
./bin/smoke-test.sh     # smoke only — slow, real .app
./bin/test.sh           # both, sequential; exits non-zero on any failure
```

## Out of scope (explicitly)

- Network-dependent fetchers (Gmail, Microsoft Graph) — would need
  recorded-tape fixtures or a mock OAuth server. Defer.
- AppleScript fetchers (Outlook mail/calendar) — depend on the user having
  Outlook installed + Automation permission granted. Defer.
- EventKit calendar fetcher — depends on Calendar permission and real
  events. Defer.
- SwiftUI snapshot tests for Mission Control — high maintenance,
  brittle to macOS theme tweaks. Defer.
- CI on GitHub Actions — manual trigger is enough for a single-user app
  today. Revisit if multiple contributors arrive.
- Window snapping via real AX API — needs Accessibility permission +
  focused window. Geometry is covered by `SnapZoneTests` but live AX
  integration isn't.

## File layout after implementation

```
Package.swift                       # +testTarget
Sources/BrotherPaul/
  AppDelegate.swift                 # handleURLEvent calls URLActionParser
  ConfigManager.swift               # env-var override in configDirectory
  GmailFetcher.swift                # uses VIPMatcher
  OutlookFetcher.swift              # uses VIPMatcher
  NotificationsFetcher.swift        # uses NotificationBlocklist
  MissionControlCoordinator.swift   # uses DigestSorter
  SnapZone.swift                    # +CGRect-based testable variants
  VerseOfTheDay.swift               # +invalidateCacheForTesting()
  URLActionParser.swift             # new — pure parser
  DigestSorter.swift                # new — pure helper
  VIPMatcher.swift                  # new — pure helper
  NotificationBlocklist.swift       # new — pure helper
  ... (other files unchanged)
Tests/BrotherPaulTests/
  AppConfigTests.swift
  ConfigManagerTests.swift
  URLActionTests.swift
  SnapZoneTests.swift
  VerseOfTheDayTests.swift
  DigestSorterTests.swift
  DigestFilterTests.swift
bin/
  smoke-test.sh                     # new
  test.sh                           # new — runs swift test + smoke-test.sh
```
