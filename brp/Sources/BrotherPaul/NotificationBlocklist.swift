import Foundation

/// Pure bundle-ID blocklist check used by NotificationsFetcher.
/// Matches exact bundle IDs (case-insensitive). Empty blocklist is pass-through.
enum NotificationBlocklist {

    static func shouldInclude(bundleID: String, blocklist: [String]) -> Bool {
        let blocked = Set(blocklist.map { $0.lowercased() })
        return !blocked.contains(bundleID.lowercased())
    }
}
