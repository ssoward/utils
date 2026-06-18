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

struct GraphConfig: Codable, Equatable {
    /// "Application (client) ID" from your Azure AD app registration.
    var clientID: String = ""
    /// Azure AD tenant: "common" for personal+work, "organizations" for work only,
    /// or your tenant GUID for SSO-restricted accounts.
    var tenant: String = "common"
    /// Refresh token captured by `bin/brpaul-graph-auth.sh`.
    var refreshToken: String = ""

    var isConfigured: Bool {
        !clientID.isEmpty && !refreshToken.isEmpty
    }
}

struct QuickLink: Codable, Identifiable, Hashable {
    var label: String
    var url: String

    var id: String { url }
}

struct GmailConfig: Codable, Equatable {
    /// OAuth client ID from your Google Cloud Console "OAuth 2.0 Client ID"
    /// (type: "Desktop app"). Leave empty to disable Gmail.
    var clientID: String = ""
    var clientSecret: String = ""
    /// Refresh token captured by `bin/brpaul-gmail-auth.sh`. We exchange it
    /// for a short-lived access token at runtime.
    var refreshToken: String = ""

    var isConfigured: Bool {
        !clientID.isEmpty && !clientSecret.isEmpty && !refreshToken.isEmpty
    }
}

struct MissionControlConfig: Codable {
    var includeCalendar: Bool
    var includeOutlook: Bool
    var includeOutlookCalendar: Bool
    var includeGraphCalendar: Bool
    var includeGmail: Bool
    var includeNotifications: Bool
    var includeVerseOfDay: Bool
    /// Look-back / look-ahead window in hours.
    var lookbackHours: Int
    /// Senders whose email is always considered priority (case-insensitive substring match against from-address or display name).
    var vipSenders: [String]
    /// App bundle IDs to filter OUT of the notification feed (e.g. ["com.apple.systemnotifications"]).
    var notificationAppBlocklist: [String]
    /// Auto-open Mission Control whenever a work session starts.
    var openOnStartWork: Bool
    /// Static links rendered as a section in Mission Control.
    var quickLinks: [QuickLink]
    var gmail: GmailConfig
    var graph: GraphConfig

    static let `default` = MissionControlConfig(
        includeCalendar: true,
        includeOutlook: true,
        includeOutlookCalendar: true,
        includeGraphCalendar: false,
        includeGmail: false,
        includeNotifications: true,
        includeVerseOfDay: true,
        lookbackHours: 24,
        vipSenders: [],
        notificationAppBlocklist: [],
        openOnStartWork: true,
        quickLinks: [],
        gmail: GmailConfig(),
        graph: GraphConfig()
    )

    enum CodingKeys: String, CodingKey {
        case includeCalendar, includeOutlook, includeOutlookCalendar, includeGraphCalendar, includeGmail, includeNotifications, includeVerseOfDay
        case lookbackHours, vipSenders, notificationAppBlocklist, openOnStartWork, quickLinks, gmail, graph
    }

    init(
        includeCalendar: Bool,
        includeOutlook: Bool,
        includeOutlookCalendar: Bool,
        includeGraphCalendar: Bool,
        includeGmail: Bool,
        includeNotifications: Bool,
        includeVerseOfDay: Bool,
        lookbackHours: Int,
        vipSenders: [String],
        notificationAppBlocklist: [String],
        openOnStartWork: Bool,
        quickLinks: [QuickLink],
        gmail: GmailConfig,
        graph: GraphConfig
    ) {
        self.includeCalendar = includeCalendar
        self.includeOutlook = includeOutlook
        self.includeOutlookCalendar = includeOutlookCalendar
        self.includeGraphCalendar = includeGraphCalendar
        self.includeGmail = includeGmail
        self.includeNotifications = includeNotifications
        self.includeVerseOfDay = includeVerseOfDay
        self.lookbackHours = lookbackHours
        self.vipSenders = vipSenders
        self.notificationAppBlocklist = notificationAppBlocklist
        self.openOnStartWork = openOnStartWork
        self.quickLinks = quickLinks
        self.gmail = gmail
        self.graph = graph
    }

    init(from decoder: Decoder) throws {
        let d = MissionControlConfig.default
        let c = try decoder.container(keyedBy: CodingKeys.self)
        includeCalendar = try c.decodeIfPresent(Bool.self, forKey: .includeCalendar) ?? d.includeCalendar
        includeOutlook = try c.decodeIfPresent(Bool.self, forKey: .includeOutlook) ?? d.includeOutlook
        includeOutlookCalendar = try c.decodeIfPresent(Bool.self, forKey: .includeOutlookCalendar) ?? d.includeOutlookCalendar
        includeGraphCalendar = try c.decodeIfPresent(Bool.self, forKey: .includeGraphCalendar) ?? d.includeGraphCalendar
        includeGmail = try c.decodeIfPresent(Bool.self, forKey: .includeGmail) ?? d.includeGmail
        includeNotifications = try c.decodeIfPresent(Bool.self, forKey: .includeNotifications) ?? d.includeNotifications
        includeVerseOfDay = try c.decodeIfPresent(Bool.self, forKey: .includeVerseOfDay) ?? d.includeVerseOfDay
        lookbackHours = try c.decodeIfPresent(Int.self, forKey: .lookbackHours) ?? d.lookbackHours
        vipSenders = try c.decodeIfPresent([String].self, forKey: .vipSenders) ?? d.vipSenders
        notificationAppBlocklist = try c.decodeIfPresent([String].self, forKey: .notificationAppBlocklist) ?? d.notificationAppBlocklist
        openOnStartWork = try c.decodeIfPresent(Bool.self, forKey: .openOnStartWork) ?? d.openOnStartWork
        quickLinks = try c.decodeIfPresent([QuickLink].self, forKey: .quickLinks) ?? d.quickLinks
        gmail = try c.decodeIfPresent(GmailConfig.self, forKey: .gmail) ?? d.gmail
        graph = try c.decodeIfPresent(GraphConfig.self, forKey: .graph) ?? d.graph
    }
}

struct VoiceWakeWordConfig: Codable, Equatable {
    /// Listen for the "Brother Paul" wake word continuously.
    var enabled: Bool = true
    /// Picovoice access key (free tier covers personal use). Empty → wake word disabled, hotkey fallback used.
    var porcupineAccessKey: String = ""
    /// Path to the trained "Brother Paul" .ppn keyword file.
    var keywordPath: String = ""

    static let `default` = VoiceWakeWordConfig()
}

struct VoiceConfig: Codable, Equatable {
    /// Master switch for the whole voice agent. OFF by default.
    var enabled: Bool
    /// Claude model id. Configurable; Haiku/Sonnet lower latency.
    var model: String
    /// output_config.effort: low | medium | high | max.
    var effort: String
    /// Per-turn output cap.
    var maxTokens: Int
    var wakeWord: VoiceWakeWordConfig
    /// Use a push-to-talk hotkey when no Porcupine key is configured.
    var pushToTalkFallback: Bool
    /// Speak replies aloud (in addition to the panel).
    var speakReplies: Bool
    /// Gate for the run_system_action tool (AppleScript/shell/open).
    var allowSystemControl: Bool
    /// Confirmation policy: tiered | confirmEverything | trust.
    var confirmTier: String

    static let `default` = VoiceConfig(
        enabled: false,
        model: "claude-opus-4-8",
        effort: "medium",
        maxTokens: 1024,
        wakeWord: .default,
        pushToTalkFallback: true,
        speakReplies: true,
        allowSystemControl: true,
        confirmTier: "tiered"
    )

    enum CodingKeys: String, CodingKey {
        case enabled, model, effort, maxTokens, wakeWord, pushToTalkFallback
        case speakReplies, allowSystemControl, confirmTier
    }

    init(enabled: Bool, model: String, effort: String, maxTokens: Int,
         wakeWord: VoiceWakeWordConfig, pushToTalkFallback: Bool,
         speakReplies: Bool, allowSystemControl: Bool, confirmTier: String) {
        self.enabled = enabled
        self.model = model
        self.effort = effort
        self.maxTokens = maxTokens
        self.wakeWord = wakeWord
        self.pushToTalkFallback = pushToTalkFallback
        self.speakReplies = speakReplies
        self.allowSystemControl = allowSystemControl
        self.confirmTier = confirmTier
    }

    init(from decoder: Decoder) throws {
        let d = VoiceConfig.default
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        effort = try c.decodeIfPresent(String.self, forKey: .effort) ?? d.effort
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? d.maxTokens
        wakeWord = try c.decodeIfPresent(VoiceWakeWordConfig.self, forKey: .wakeWord) ?? d.wakeWord
        pushToTalkFallback = try c.decodeIfPresent(Bool.self, forKey: .pushToTalkFallback) ?? d.pushToTalkFallback
        speakReplies = try c.decodeIfPresent(Bool.self, forKey: .speakReplies) ?? d.speakReplies
        allowSystemControl = try c.decodeIfPresent(Bool.self, forKey: .allowSystemControl) ?? d.allowSystemControl
        confirmTier = try c.decodeIfPresent(String.self, forKey: .confirmTier) ?? d.confirmTier
    }
}

struct AppConfig: Codable {
    var hideOthersAfterLaunch: Bool
    var defaultMode: String
    var modes: [LaunchMode]
    var enableSnap: Bool
    var enableDragSnap: Bool
    var missionControl: MissionControlConfig
    var voice: VoiceConfig

    enum CodingKeys: String, CodingKey {
        case hideOthersAfterLaunch, defaultMode, modes, enableSnap, enableDragSnap, missionControl, voice
    }

    init(
        hideOthersAfterLaunch: Bool,
        defaultMode: String,
        modes: [LaunchMode],
        enableSnap: Bool = true,
        enableDragSnap: Bool = true,
        missionControl: MissionControlConfig = .default,
        voice: VoiceConfig = .default
    ) {
        self.hideOthersAfterLaunch = hideOthersAfterLaunch
        self.defaultMode = defaultMode
        self.modes = modes
        self.enableSnap = enableSnap
        self.enableDragSnap = enableDragSnap
        self.missionControl = missionControl
        self.voice = voice
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hideOthersAfterLaunch = try c.decode(Bool.self, forKey: .hideOthersAfterLaunch)
        defaultMode = try c.decode(String.self, forKey: .defaultMode)
        modes = try c.decode([LaunchMode].self, forKey: .modes)
        enableSnap = try c.decodeIfPresent(Bool.self, forKey: .enableSnap) ?? true
        enableDragSnap = try c.decodeIfPresent(Bool.self, forKey: .enableDragSnap) ?? true
        missionControl = try c.decodeIfPresent(MissionControlConfig.self, forKey: .missionControl) ?? .default
        voice = try c.decodeIfPresent(VoiceConfig.self, forKey: .voice) ?? .default
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
