import Foundation

enum DigestSource: String {
    case calendar
    case outlook
    case gmail
    case notifications
}

struct DigestItem: Identifiable {
    let id = UUID()
    let source: DigestSource
    let title: String
    let subtitle: String?
    let timestamp: Date?
    /// Higher = more important.
    let priority: Int
    /// Optional click target (URL or app-deep-link).
    let openURL: URL?
}

struct SectionResult {
    var items: [DigestItem]
    /// User-facing status: nil if fine, otherwise a short reason ("Calendar access denied", "Outlook not running", etc.).
    var status: String?
}

struct Digest {
    var generatedAt: Date
    var verse: Verse?
    var events: SectionResult
    var emails: SectionResult
    var notifications: SectionResult
}
