import Foundation

struct LaunchMode: Codable, Identifiable, Hashable {
    var name: String
    var apps: [String]
    var urls: [String]

    var id: String { name }

    init(name: String, apps: [String], urls: [String] = []) {
        self.name = name
        self.apps = apps
        self.urls = urls
    }
}

struct AppConfig: Codable {
    var hideOthersAfterLaunch: Bool
    var defaultMode: String
    var modes: [LaunchMode]
    var enableSnap: Bool
    var enableDragSnap: Bool

    enum CodingKeys: String, CodingKey {
        case hideOthersAfterLaunch, defaultMode, modes, enableSnap, enableDragSnap
    }

    init(
        hideOthersAfterLaunch: Bool,
        defaultMode: String,
        modes: [LaunchMode],
        enableSnap: Bool = true,
        enableDragSnap: Bool = true
    ) {
        self.hideOthersAfterLaunch = hideOthersAfterLaunch
        self.defaultMode = defaultMode
        self.modes = modes
        self.enableSnap = enableSnap
        self.enableDragSnap = enableDragSnap
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hideOthersAfterLaunch = try c.decode(Bool.self, forKey: .hideOthersAfterLaunch)
        defaultMode = try c.decode(String.self, forKey: .defaultMode)
        modes = try c.decode([LaunchMode].self, forKey: .modes)
        enableSnap = try c.decodeIfPresent(Bool.self, forKey: .enableSnap) ?? true
        enableDragSnap = try c.decodeIfPresent(Bool.self, forKey: .enableDragSnap) ?? true
    }

    static let `default` = AppConfig(
        hideOthersAfterLaunch: true,
        defaultMode: "Full",
        modes: [
            LaunchMode(
                name: "Full",
                apps: ["Microsoft Teams", "Microsoft Outlook", "Google Chrome", "Slack"]
            ),
            LaunchMode(
                name: "Deep Work",
                apps: ["Google Chrome", "Slack", "Notion"]
            ),
            LaunchMode(
                name: "Meetings",
                apps: ["Microsoft Teams", "Microsoft Outlook", "zoom.us"]
            ),
            LaunchMode(
                name: "Admin",
                apps: ["Microsoft Outlook", "Google Chrome"],
                urls: ["https://mail.google.com"]
            )
        ]
    )

    func mode(named name: String) -> LaunchMode? {
        modes.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
