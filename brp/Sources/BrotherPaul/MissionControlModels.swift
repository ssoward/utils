import Foundation

enum DigestSource: String {
    case calendar
    case outlook
    case gmail
    case notifications
    case reminders
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
    /// Identifier of the backing external object (e.g. an EKReminder), when the
    /// row supports actions like "complete". nil for read-only sources.
    let externalID: String?

    init(
        source: DigestSource,
        title: String,
        subtitle: String?,
        timestamp: Date?,
        priority: Int,
        openURL: URL?,
        externalID: String? = nil
    ) {
        self.source = source
        self.title = title
        self.subtitle = subtitle
        self.timestamp = timestamp
        self.priority = priority
        self.openURL = openURL
        self.externalID = externalID
    }
}

struct SectionResult {
    var items: [DigestItem]
    /// User-facing status: nil if fine, otherwise a short reason ("Calendar access denied", "Outlook not running", etc.).
    var status: String?
}

struct Digest {
    var generatedAt: Date
    var verse: Verse?
    var reminder: Reminder?
    var events: SectionResult
    var emails: SectionResult
    var reminders: SectionResult
    var notifications: SectionResult
}
