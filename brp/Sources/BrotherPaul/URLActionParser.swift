import Foundation

/// Parsed result of a brotherpaul:// URL.
enum URLAction: Equatable {
    case start(mode: String?)
    case stop(mode: String?)
    case unknown(action: String)
}

/// Pure parser for brotherpaul:// URLs. No side effects, no I/O.
enum URLActionParser {

    /// Returns the parsed action, or nil if the input is not a parseable URL.
    static func parse(_ urlString: String) -> URLAction? {
        guard let components = URLComponents(string: urlString) else { return nil }

        let action = components.host
            ?? components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !action.isEmpty else { return nil }

        let mode = components.queryItems?
            .first { $0.name.caseInsensitiveCompare("mode") == .orderedSame }?
            .value

        switch action.lowercased() {
        case "start":
            return .start(mode: mode)
        case "stop", "end":
            return .stop(mode: mode)
        default:
            return .unknown(action: action)
        }
    }
}
