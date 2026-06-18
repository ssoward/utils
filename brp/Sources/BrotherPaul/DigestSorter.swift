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
