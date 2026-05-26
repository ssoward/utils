import SwiftUI
import AppKit

struct MissionControlView: View {
    @ObservedObject var coordinator: MissionControlCoordinator

    @AppStorage("mc.expand.events")        private var expandEvents = true
    @AppStorage("mc.expand.emails")        private var expandEmails = true
    @AppStorage("mc.expand.notifications") private var expandNotifications = true
    @AppStorage("mc.expand.links")         private var expandLinks = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if let digest = coordinator.digest {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let verse = digest.verse {
                            verseCard(verse)
                        }
                        quickLinksSection()
                        section(
                            title: "Upcoming Events",
                            icon: "calendar",
                            result: digest.events,
                            isExpanded: $expandEvents,
                            emptyText: "Nothing scheduled."
                        )
                        section(
                            title: "Priority Email",
                            icon: "envelope.fill",
                            result: digest.emails,
                            isExpanded: $expandEmails,
                            emptyText: "Inbox zero."
                        )
                        section(
                            title: "Recent Notifications",
                            icon: "bell.fill",
                            result: digest.notifications,
                            isExpanded: $expandNotifications,
                            emptyText: "All quiet."
                        )
                    }
                    .padding(18)
                }

                HStack(spacing: 12) {
                    Button("Expand all") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            expandEvents = true; expandEmails = true; expandNotifications = true; expandLinks = true
                        }
                    }
                    Button("Collapse all") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            expandEvents = false; expandEmails = false; expandNotifications = false; expandLinks = false
                        }
                    }
                    Spacer()
                }
                .font(.caption)
                .padding(.horizontal, 18)
                .padding(.bottom, 4)
            } else if coordinator.isLoading {
                ProgressView("Fetching digest…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Click Refresh to build today's digest.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            footer
        }
        .frame(minWidth: 620, minHeight: 540)
        .textSelection(.enabled)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "scope")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mission Control").font(.title2).bold()
                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await coordinator.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(coordinator.isLoading)
        }
        .padding(16)
    }

    private var headerSubtitle: String {
        guard let digest = coordinator.digest else {
            return Date().formatted(date: .complete, time: .omitted)
        }
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .short
        return f.string(from: digest.generatedAt)
    }

    private var footer: some View {
        HStack {
            if coordinator.isLoading {
                ProgressView().scaleEffect(0.6)
                Text("Refreshing…").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Local · private · no analytics")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func section(title: String, icon: String, result: SectionResult, isExpanded: Binding<Bool>, emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Image(systemName: icon).foregroundStyle(.tint)
                    Text(title).font(.headline)
                    Text("\(result.items.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(Color.secondary.opacity(0.15))
                        )
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                if let status = result.status, result.items.isEmpty {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else if result.items.isEmpty {
                    Text(emptyText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 6) {
                        ForEach(result.items) { item in
                            row(item)
                        }
                    }
                    if let status = result.status {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func row(_ item: DigestItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            priorityDot(item.priority)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .lineLimit(2)
                if let sub = item.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let ts = item.timestamp {
                Text(relative(ts))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = item.openURL { NSWorkspace.shared.open(url) }
        }
    }

    private func priorityDot(_ priority: Int) -> some View {
        let color: Color = priority >= 90 ? .red : priority >= 70 ? .orange : priority >= 50 ? .blue : .gray
        return Circle().fill(color).frame(width: 8, height: 8).padding(.top, 6)
    }

    @ViewBuilder
    private func quickLinksSection() -> some View {
        let links = ConfigManager.shared.config.missionControl.quickLinks
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        expandLinks.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: expandLinks ? "chevron.down" : "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                        Image(systemName: "link").foregroundStyle(.tint)
                        Text("Quick Links").font(.headline)
                        Text("\(links.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expandLinks {
                    VStack(spacing: 6) {
                        ForEach(links) { link in
                            quickLinkRow(link)
                        }
                    }
                }
            }
        }
    }

    private func quickLinkRow(_ link: QuickLink) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.right.square")
                .foregroundStyle(.tint)
            Text(link.label)
                .font(.body)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = URL(string: link.url) { NSWorkspace.shared.open(url) }
        }
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func verseCard(_ verse: Verse) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                Text("\u{201C}\(verse.text)\u{201D}")
                    .font(.body.italic())
                    .foregroundStyle(.primary)
                Text("\u{2014} \(verse.reference)\(verse.source.map { " (\($0))" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Button {
                coordinator.shuffleVerse()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.body)
            }
            .buttonStyle(.borderless)
            .help("Show a different verse")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08))
        )
    }
}
