// brp/Sources/BrotherPaul/Agent/ScheduleQueryExecutor.swift
import Foundation

struct ScheduleQueryExecutor: ToolExecutor {
    @MainActor
    func execute(_ call: ToolCall) async -> ExecutionOutcome {
        let coordinator = MissionControlCoordinator()
        await coordinator.refresh()
        guard let digest = coordinator.digest else {
            return .ok("I couldn't load your schedule right now.")
        }

        let df = DateFormatter()
        df.dateFormat = "EEE h:mm a"

        func format(_ section: SectionResult, label: String, limit: Int) -> String {
            let lines = section.items.prefix(limit).map { item -> String in
                let when = item.timestamp.map { " (\(df.string(from: $0)))" } ?? ""
                let sub = item.subtitle.map { " — \($0)" } ?? ""
                return "• \(item.title)\(sub)\(when)"
            }
            return lines.isEmpty ? "\(label): nothing." : "\(label):\n" + lines.joined(separator: "\n")
        }

        let sources = Set((call.input["sources"]?.arrayValue ?? []).compactMap { $0.stringValue })
        let wantAll = sources.isEmpty
        var parts: [String] = []
        if wantAll || sources.contains("calendar") { parts.append(format(digest.events, label: "Upcoming events", limit: 5)) }
        if wantAll || sources.contains("email") { parts.append(format(digest.emails, label: "Priority email", limit: 5)) }
        if sources.contains("notifications") { parts.append(format(digest.notifications, label: "Recent notifications", limit: 5)) }

        return .ok(parts.joined(separator: "\n\n"))
    }
}
