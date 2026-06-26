import Foundation

enum GraphMailFetcher {

    static func fetchUnread(config: GraphConfig, vipSenders: [String], hours: Int) async -> SectionResult {
        guard config.isConfigured else {
            return SectionResult(items: [], status: "Microsoft Graph not configured — run brp/bin/brpaul-graph-auth.sh.")
        }

        let token: String
        do {
            token = try await refreshAccessToken(config: config)
        } catch {
            return SectionResult(items: [], status: "Graph token refresh failed: \(error.localizedDescription).")
        }

        do {
            let items = try await fetchMessages(token: token, vipSenders: vipSenders, hours: hours)
            if items.isEmpty {
                return SectionResult(items: [], status: "No unread Outlook mail in the last \(hours)h (via Graph).")
            }
            return SectionResult(items: items, status: nil)
        } catch {
            return SectionResult(items: [], status: "Graph mail API error: \(error.localizedDescription).")
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
            "scope": "Mail.Read offline_access",
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
        return try parseAccessToken(data)
    }

    // MARK: - /me/messages

    private static func fetchMessages(token: String, vipSenders: [String], hours: Int) async throws -> [DigestItem] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let cutoff = Calendar.current.date(byAdding: .hour, value: -hours, to: Date()) ?? Date()
        let cutoffStr = iso.string(from: cutoff)

        var comps = URLComponents(string: "https://graph.microsoft.com/v1.0/me/messages")!
        comps.queryItems = [
            URLQueryItem(name: "$filter", value: "isRead eq false and receivedDateTime ge \(cutoffStr)"),
            URLQueryItem(name: "$select", value: "subject,from,receivedDateTime,webLink"),
            URLQueryItem(name: "$orderby", value: "receivedDateTime desc"),
            URLQueryItem(name: "$top", value: "50"),
        ]

        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(300) ?? "(no body)"
            throw NSError(
                domain: "Graph", code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: String(snippet)]
            )
        }

        return parseMessages(data, vipSenders: vipSenders)
    }

    // MARK: - Pure parsers (network-free, unit-tested)

    /// Extracts the `access_token` from a Microsoft identity token-refresh
    /// response. Throws if the field is absent (surfaces as an auth error).
    static func parseAccessToken(_ data: Data) throws -> String {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let token = json["access_token"] as? String else {
            throw NSError(domain: "Graph", code: 2, userInfo: [NSLocalizedDescriptionKey: "no access_token in response"])
        }
        return token
    }

    /// Builds DigestItems from a Graph `/me/messages` response. Malformed
    /// bodies yield an empty list rather than an error.
    static func parseMessages(_ data: Data, vipSenders: [String]) -> [DigestItem] {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let messages = json["value"] as? [[String: Any]] ?? []

        // receivedDateTime is ISO-8601 UTC: "2026-05-31T14:23:00Z"
        let utc = ISO8601DateFormatter()
        utc.formatOptions = [.withInternetDateTime]
        let utcFrac = ISO8601DateFormatter()
        utcFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var items: [DigestItem] = []
        for msg in messages {
            let subject = (msg["subject"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "(no subject)"
            let receivedStr = msg["receivedDateTime"] as? String ?? ""
            let received = utc.date(from: receivedStr) ?? utcFrac.date(from: receivedStr)
            let webLink = (msg["webLink"] as? String).flatMap(URL.init(string:))

            // from = { "emailAddress": { "name": "...", "address": "..." } }
            let fromObj = (msg["from"] as? [String: Any])?["emailAddress"] as? [String: Any]
            let senderName = fromObj?["name"] as? String ?? ""
            let senderAddr = fromObj?["address"] as? String ?? ""
            let sender = senderName.isEmpty ? senderAddr : senderName

            let priority = VIPMatcher.isVIP(haystacks: [sender, senderAddr, subject],
                                            vipSenders: vipSenders) ? 90 : 50

            items.append(DigestItem(
                source: .outlook,
                title: subject,
                subtitle: sender,
                timestamp: received,
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
