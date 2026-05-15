import Foundation

enum GraphCalendarFetcher {

    static func fetchUpcoming(config: GraphConfig, hours: Int) async -> SectionResult {
        guard config.isConfigured else {
            return SectionResult(items: [], status: "Microsoft Graph not configured — see USER_GUIDE.md → Mission Control → Outlook calendar via Graph.")
        }

        let token: String
        do {
            token = try await refreshAccessToken(config: config)
        } catch {
            return SectionResult(items: [], status: "Graph token refresh failed: \(error.localizedDescription).")
        }

        do {
            let items = try await fetchEvents(token: token, hours: hours)
            if items.isEmpty {
                return SectionResult(items: [], status: "No Outlook events in the next \(hours)h (via Graph).")
            }
            return SectionResult(items: items, status: nil)
        } catch {
            return SectionResult(items: [], status: "Graph API error: \(error.localizedDescription).")
        }
    }

    // MARK: - OAuth refresh

    private static func refreshAccessToken(config: GraphConfig) async throws -> String {
        let tenant = config.tenant.isEmpty ? "common" : config.tenant
        let url = URL(string: "https://login.microsoftonline.com/\(tenant)/oauth2/v2.0/token")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id": config.clientID,
            "refresh_token": config.refreshToken,
            "grant_type": "refresh_token",
            "scope": "Calendars.Read offline_access",
        ]
        req.httpBody = formEncode(body).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(300) ?? "(no body)"
            throw NSError(
                domain: "Graph", code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: "token refresh: \(snippet)"]
            )
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let token = json["access_token"] as? String else {
            throw NSError(domain: "Graph", code: 2, userInfo: [NSLocalizedDescriptionKey: "no access_token in response"])
        }
        return token
    }

    // MARK: - Calendar view

    private static func fetchEvents(token: String, hours: Int) async throws -> [DigestItem] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let now = Date()
        let end = Calendar.current.date(byAdding: .hour, value: hours, to: now) ?? now

        var comps = URLComponents(string: "https://graph.microsoft.com/v1.0/me/calendarview")!
        comps.queryItems = [
            URLQueryItem(name: "startDateTime", value: iso.string(from: now)),
            URLQueryItem(name: "endDateTime", value: iso.string(from: end)),
            URLQueryItem(name: "$select", value: "subject,start,end,location,isAllDay,webLink"),
            URLQueryItem(name: "$orderby", value: "start/dateTime"),
            URLQueryItem(name: "$top", value: "50"),
        ]

        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Ask Graph to return start/end in the user's local time zone so we can
        // format directly without a tz parse.
        req.setValue("outlook.timezone=\"\(TimeZone.current.identifier)\"", forHTTPHeaderField: "Prefer")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(300) ?? "(no body)"
            throw NSError(
                domain: "Graph", code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: String(snippet)]
            )
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let events = json["value"] as? [[String: Any]] ?? []

        // Graph's local-time strings look like "2026-05-15T13:00:00.0000000".
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = TimeZone.current
        local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS"
        let localNoFrac = DateFormatter()
        localNoFrac.locale = Locale(identifier: "en_US_POSIX")
        localNoFrac.timeZone = TimeZone.current
        localNoFrac.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let utcWithZ = ISO8601DateFormatter()
        utcWithZ.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let utcNoFrac = ISO8601DateFormatter()
        utcNoFrac.formatOptions = [.withInternetDateTime]

        func parseDate(_ s: String) -> Date? {
            local.date(from: s) ?? localNoFrac.date(from: s) ?? utcWithZ.date(from: s) ?? utcNoFrac.date(from: s)
        }

        let timeFmt = DateFormatter()
        timeFmt.dateStyle = .none
        timeFmt.timeStyle = .short
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "EEE"

        var items: [DigestItem] = []
        for ev in events {
            let subject = (ev["subject"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "(no subject)"
            let startObj = ev["start"] as? [String: Any]
            let endObj = ev["end"] as? [String: Any]
            let locObj = ev["location"] as? [String: Any]
            let isAllDay = ev["isAllDay"] as? Bool ?? false
            let webLink = (ev["webLink"] as? String).flatMap(URL.init(string:))

            guard let startStr = startObj?["dateTime"] as? String,
                  let start = parseDate(startStr) else { continue }
            let end = (endObj?["dateTime"] as? String).flatMap(parseDate)
            let location = (locObj?["displayName"] as? String) ?? ""

            let timeStr: String
            if isAllDay {
                timeStr = "All day"
            } else {
                let s = timeFmt.string(from: start)
                let when = end.map { "\(s) – \(timeFmt.string(from: $0))" } ?? s
                timeStr = Calendar.current.isDateInToday(start) ? when : "\(dayFmt.string(from: start)) \(when)"
            }
            let subtitle = location.isEmpty ? timeStr : "\(timeStr)  ·  \(location)"

            let minutesAway = Int(start.timeIntervalSinceNow / 60)
            let priority: Int = minutesAway <= 15 ? 100 : (minutesAway <= 60 ? 80 : 60)

            items.append(DigestItem(
                source: .calendar,
                title: subject,
                subtitle: subtitle,
                timestamp: start,
                priority: priority,
                openURL: webLink
            ))
        }
        return items
    }

    // MARK: - helpers

    private static func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
    }
}
