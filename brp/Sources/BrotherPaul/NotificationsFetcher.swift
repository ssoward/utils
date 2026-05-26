import Foundation
import SQLite3

enum NotificationsFetcher {

    static func fetchRecent(hours: Int, appBlocklist: [String]) async -> SectionResult {
        await Task.detached(priority: .userInitiated) { run(hours: hours, blocklist: appBlocklist) }.value
    }

    private static func run(hours: Int, blocklist: [String]) -> SectionResult {
        let dbPath = locateDB()
        guard FileManager.default.fileExists(atPath: dbPath) else {
            return SectionResult(items: [], status: "Notification database not found at \(dbPath).")
        }

        var db: OpaquePointer?
        let openResult = sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let db = db else {
            // SQLITE_CANTOPEN is the typical signature of missing Full Disk Access.
            return SectionResult(
                items: [],
                status: "Couldn't read the notification database — grant Full Disk Access to BrotherPaul in System Settings → Privacy & Security → Full Disk Access."
            )
        }
        defer { sqlite3_close(db) }

        // delivered_date is seconds-since-2001 (Cocoa reference date).
        let cutoff = Date().addingTimeInterval(TimeInterval(-hours * 3600)).timeIntervalSinceReferenceDate

        let sql = """
        SELECT r.delivered_date, a.identifier, r.data
        FROM record r
        JOIN app a ON r.app_id = a.app_id
        WHERE r.delivered_date > ?
        ORDER BY r.delivered_date DESC
        LIMIT 200
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return SectionResult(items: [], status: "Notification query prepare failed (schema may have changed in this macOS version).")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, cutoff)

        var items: [DigestItem] = []
        let blocklistLower = Set(blocklist.map { $0.lowercased() })

        while sqlite3_step(stmt) == SQLITE_ROW {
            let deliveredSinceRef = sqlite3_column_double(stmt, 0)
            let identifier = String(cString: sqlite3_column_text(stmt, 1))

            if blocklistLower.contains(identifier.lowercased()) { continue }

            guard let blobPtr = sqlite3_column_blob(stmt, 2) else { continue }
            let blobLen = sqlite3_column_bytes(stmt, 2)
            let blob = Data(bytes: blobPtr, count: Int(blobLen))

            guard let parsed = parsePayload(blob) else { continue }

            let title = parsed.title.isEmpty ? identifier : parsed.title
            let body = parsed.body
            let subtitle: String
            if parsed.subtitle.isEmpty {
                subtitle = body.isEmpty ? identifier : body
            } else if body.isEmpty {
                subtitle = parsed.subtitle
            } else {
                subtitle = "\(parsed.subtitle) — \(body)"
            }

            let date = Date(timeIntervalSinceReferenceDate: deliveredSinceRef)
            items.append(DigestItem(
                source: .notifications,
                title: title,
                subtitle: subtitle,
                timestamp: date,
                priority: 30,
                openURL: nil
            ))
        }

        if items.isEmpty {
            return SectionResult(items: [], status: "No notifications in the last \(hours)h (after blocklist).")
        }
        return SectionResult(items: items, status: nil)
    }

    // MARK: - DB location

    private static func locateDB() -> String {
        let base = ("~/Library/Group Containers/group.com.apple.usernoted/db2" as NSString).expandingTildeInPath
        return base + "/db"
    }

    // MARK: - Payload parsing

    private struct Payload {
        var title: String = ""
        var subtitle: String = ""
        var body: String = ""
    }

    /// Notification payloads are Cocoa binary plists. Schema varies across
    /// macOS versions; we look in `req` (recent versions) and fall back to
    /// scanning common keys at the top level.
    private static func parsePayload(_ data: Data) -> Payload? {
        guard let raw = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return nil
        }
        var payload = Payload()

        func extract(from dict: [String: Any]) {
            // Recent macOS: titl / subt / body. Older: title / subtitle / informativeText.
            payload.title = (dict["titl"] as? String) ?? (dict["title"] as? String) ?? payload.title
            payload.subtitle = (dict["subt"] as? String) ?? (dict["subtitle"] as? String) ?? payload.subtitle
            payload.body = (dict["body"] as? String) ?? (dict["informativeText"] as? String) ?? payload.body
        }

        if let dict = raw as? [String: Any] {
            if let req = dict["req"] as? [String: Any] {
                extract(from: req)
            }
            extract(from: dict)
        }

        if payload.title.isEmpty && payload.body.isEmpty && payload.subtitle.isEmpty {
            return nil
        }
        return payload
    }
}
