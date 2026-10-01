import AppKit

/// What the menu-bar icon should say about open todos. Pure (except the
/// image/attributed helpers) so the badge rules are unit-testable.
struct TodoBadge: Equatable {
    enum Level: Equatable { case none, dueToday, overdue }

    let level: Level
    /// Text drawn next to the icon (" 3"), empty when there's nothing to flag.
    let text: String
    let toolTip: String

    init(snapshot: TodoSnapshot, enabled: Bool) {
        let count = snapshot.attentionCount
        if !enabled { level = .none }
        else if snapshot.overdueCount > 0 { level = .overdue }
        else if snapshot.dueTodayCount > 0 { level = .dueToday }
        else { level = .none }

        text = (enabled && count > 0) ? " \(count)" : ""

        var parts: [String] = []
        if snapshot.overdueCount > 0 { parts.append("\(snapshot.overdueCount) overdue") }
        if snapshot.dueTodayCount > 0 { parts.append("\(snapshot.dueTodayCount) due today") }
        toolTip = parts.isEmpty
            ? "Brother Paul — start my work"
            : "Brother Paul — " + parts.joined(separator: ", ")
    }

    /// "TODOS · 2 overdue · 1 today" header for the menu's todo section.
    static func menuHeader(for snap: TodoSnapshot, loaded: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "TODOS", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        let detail: String
        if !loaded {
            detail = "loading…"
        } else if snap.items.isEmpty {
            detail = snap.status ?? "all clear"
        } else {
            var bits: [String] = []
            if snap.overdueCount > 0 { bits.append("\(snap.overdueCount) overdue") }
            if snap.dueTodayCount > 0 { bits.append("\(snap.dueTodayCount) today") }
            bits.append("\(snap.items.count) open")
            detail = bits.joined(separator: " · ")
        }
        result.append(NSAttributedString(string: "  ·  \(detail)", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: snap.overdueCount > 0 ? NSColor.systemRed : NSColor.secondaryLabelColor,
        ]))
        return result
    }

    /// Small colored dot matching Mission Control's priority dots.
    static func dotImage(priority: Int) -> NSImage {
        let color: NSColor = priority >= 90 ? .systemRed : priority >= 70 ? .systemOrange : priority >= 50 ? .systemBlue : .systemGray
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
