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
