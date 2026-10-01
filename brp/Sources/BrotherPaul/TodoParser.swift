import Foundation

/// Pulls a due date out of a quick-capture title, so "Email Bob tomorrow 3pm"
/// becomes title "Email Bob" due tomorrow at 3 PM. Only future dates count —
/// "fix the 9/12 regression" keeps its text and gets no due date.
enum TodoParser {

    struct Result: Equatable {
        var title: String
        var dueDate: Date?
    }

    static func parse(_ raw: String, now: Date = Date()) -> Result {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        else { return Result(title: text, dueDate: nil) }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector.matches(in: text, options: [], range: range).last,
              let date = match.date, date > now,
              let swiftRange = Range(match.range, in: text)
        else { return Result(title: text, dueDate: nil) }

        var title = text
        title.removeSubrange(swiftRange)
        title = title
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",-–—@")))
        // Strip a dangling connector left behind ("Call mom on" / "Pay rent by").
        for suffix in [" on", " at", " by", " due"] where title.lowercased().hasSuffix(suffix) {
            title = String(title.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        guard !title.isEmpty else { return Result(title: text, dueDate: date) }
        return Result(title: title, dueDate: date)
    }
}
