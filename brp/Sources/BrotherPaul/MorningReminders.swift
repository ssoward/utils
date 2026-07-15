import Foundation

struct Reminder: Codable, Equatable {
    let text: String
    /// Free-form attribution printed as the citation suffix — a person, a
    /// date, a journal, whatever the entry came from. Optional so entries
    /// without it still decode.
    let source: String?

    init(text: String, source: String? = nil) {
        self.text = text
        self.source = source
    }
}

/// Personal daily reminders shown as a card in Mission Control, rotated the
/// same way as Verse of the Day. Unlike verses there is no built-in default
/// list — the content is the user's own (promises, affirmations, counsel they
/// want in front of them each morning) and lives only in
/// `~/Library/Application Support/BrotherPaul/reminders.json`, never in the
/// app source. An empty or missing file simply hides the card.
enum MorningReminders {

    /// Today's reminder, or nil when the user has none configured.
    /// Selection is day-of-year modulo count, matching VerseOfTheDay.
    static func todays(now: Date = Date()) -> Reminder? {
        let reminders = load()
        guard !reminders.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: now) ?? 1
        return reminders[(day - 1) % reminders.count]
    }

    /// A random reminder from the same pool, never equal to the one passed
    /// in (unless the pool has a single entry). Nil when none configured.
    static func randomReminder(excluding current: Reminder?) -> Reminder? {
        let reminders = load()
        guard !reminders.isEmpty else { return nil }
        guard let current = current, reminders.count > 1 else {
            return reminders.randomElement()
        }
        let pool = reminders.filter { $0 != current }
        return pool.randomElement() ?? reminders[0]
    }

    /// Path of the user-editable reminders file.
    static var customFileURL: URL {
        ConfigManager.shared.configDirectory.appendingPathComponent("reminders.json")
    }

    /// Create an empty reminders file so "Edit Morning Reminders…" has
    /// something to open. Never overwrites an existing file — the content is
    /// personal and there are no shipped defaults to push out.
    static func installSeed() {
        let url = customFileURL
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? "[\n]\n".data(using: .utf8)?.write(to: url, options: .atomic)
    }

    /// Read fresh on every call — the file is small, refreshes are rare, and
    /// this lets edits show up on the next Mission Control refresh without
    /// relaunching the app.
    private static func load() -> [Reminder] {
        guard let data = try? Data(contentsOf: customFileURL),
              let reminders = try? JSONDecoder().decode([Reminder].self, from: data)
        else { return [] }
        return reminders
    }
}
