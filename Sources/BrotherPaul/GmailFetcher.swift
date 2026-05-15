import Foundation

enum GmailFetcher {

    static func fetchUnread(config: GmailConfig, vipSenders: [String]) async -> SectionResult {
        guard config.isConfigured else {
            return SectionResult(items: [], status: "Gmail not configured — see USER_GUIDE.md → Mission Control → Gmail.")
        }

        let token: String
        do {
            token = try await refreshAccessToken(config: config)
        } catch {
            return SectionResult(items: [], status: "Gmail token refresh failed: \(error.localizedDescription).")
        }

        do {
            let ids = try await listMessageIDs(query: "is:unread newer_than:1d", token: token)
            var items: [DigestItem] = []
            for id in ids.prefix(20) {
                if let item = try await fetchMessage(id: id, token: token, vipSenders: vipSenders) {
                    items.append(item)
                }
            }
            if items.isEmpty {
                return SectionResult(items: [], status: "No unread Gmail in the last 24h.")
            }
            return SectionResult(items: items, status: nil)
        } catch {
            return SectionResult(items: [], status: "Gmail API error: \(error.localizedDescription).")
        }
    }

    // MARK: - OAuth refresh

    private static func refreshAccessToken(config: GmailConfig) async throws -> String {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id": config.clientID,
            "client_secret": config.clientSecret,
            "refresh_token": config.refreshToken,
            "grant_type": "refresh_token",
        ]
        req.httpBody = formEncode(body).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let snippet = String(data: data, encoding: .utf8) ?? "(no body)"
            throw NSError(domain: "Gmail", code: 1, userInfo: [NSLocalizedDescriptionKey: "token refresh \((response as? HTTPURLResponse)?.statusCode ?? -1): \(snippet)"])
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let token = json["access_token"] as? String else {
            throw NSError(domain: "Gmail", code: 2, userInfo: [NSLocalizedDescriptionKey: "no access_token in response"])
        }
        return token
    }

    // MARK: - Gmail API

    private static func listMessageIDs(query: String, token: String) async throws -> [String] {
        var comps = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: "20"),
        ]
        let data = try await get(comps.url!, token: token)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let messages = json["messages"] as? [[String: Any]] ?? []
        return messages.compactMap { $0["id"] as? String }
    }

    private static func fetchMessage(id: String, token: String, vipSenders: [String]) async throws -> DigestItem? {
        var comps = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)")!
        comps.queryItems = [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "Date"),
        ]
        let data = try await get(comps.url!, token: token)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let payload = json["payload"] as? [String: Any]
        let headers = payload?["headers"] as? [[String: String]] ?? []
        var subject = "(no subject)"
        var from = ""
        var dateStr = ""
        for h in headers {
            switch h["name"]?.lowercased() {
            case "subject": subject = h["value"] ?? subject
            case "from":    from = h["value"] ?? from
            case "date":    dateStr = h["value"] ?? dateStr
            default: break
            }
        }
        let internalDate = (json["internalDate"] as? String).flatMap(Double.init)
        let timestamp: Date? = {
            if let ms = internalDate { return Date(timeIntervalSince1970: ms / 1000) }
            return rfc2822Date(dateStr)
        }()

        let isVIP = vipSenders.contains { vip in
            let v = vip.lowercased()
            return !v.isEmpty && from.lowercased().contains(v)
        }
        let priority = isVIP ? 90 : 50

        let openURL = URL(string: "https://mail.google.com/mail/u/0/#inbox/\(id)")
        return DigestItem(
            source: .gmail,
            title: subject,
            subtitle: from,
            timestamp: timestamp,
            priority: priority,
            openURL: openURL
        )
    }

    // MARK: - HTTP helpers

    private static func get(_ url: URL, token: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(200) ?? "(no body)"
            throw NSError(domain: "Gmail", code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: String(snippet)])
        }
        return data
    }

    private static func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
    }

    private static func rfc2822Date(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f.date(from: s)
    }
}
