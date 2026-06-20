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
