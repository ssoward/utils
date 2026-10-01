import SwiftUI
import AppKit

struct MissionControlView: View {
    @ObservedObject var coordinator: MissionControlCoordinator
    @ObservedObject var todos: TodoMonitor = .shared

    @AppStorage("mc.expand.events")        private var expandEvents = true
    @AppStorage("mc.expand.emails")        private var expandEmails = true
    @AppStorage("mc.expand.todos")         private var expandTodos = true
    @AppStorage("mc.expand.notifications") private var expandNotifications = true
    @AppStorage("mc.expand.links")         private var expandLinks = true

    // Quick-add todo state.
    @State private var newTodoTitle: String = ""
    @State private var newTodoHasDue: Bool = false
    @State private var newTodoDue: Date = Date().addingTimeInterval(3600)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if let digest = coordinator.digest {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Todos first: they're the thing that's easiest to miss.
                        if ConfigManager.shared.config.missionControl.includeReminders {
                            todosSection(todos.snapshot)
                        }
                        if let verse = digest.verse {
                            verseCard(verse)
                        }
                        if let reminder = digest.reminder {
                            reminderCard(reminder)
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
                            expandEvents = true; expandEmails = true; expandTodos = true; expandNotifications = true; expandLinks = true
                        }
                    }
                    Button("Collapse all") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            expandEvents = false; expandEmails = false; expandTodos = false; expandNotifications = false; expandLinks = false
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

    // MARK: - Todos

    @ViewBuilder
    private func todosSection(_ snap: TodoSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expandTodos.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expandTodos ? "chevron.down" : "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Image(systemName: "checklist")
                        .foregroundStyle(snap.overdueCount > 0 ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
                    Text("Todos & Reminders").font(.headline)
                    Text("\(snap.items.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    if snap.overdueCount > 0 {
                        countPill("\(snap.overdueCount) overdue", color: .red)
                    }
                    if snap.dueTodayCount > 0 {
                        countPill("\(snap.dueTodayCount) today", color: .orange)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expandTodos {
                quickAddRow

                if !todos.hasLoaded {
                    ProgressView().scaleEffect(0.6)
                } else if snap.items.isEmpty {
                    Text(snap.status ?? "Nothing to do.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 6) {
                        ForEach(snap.items, id: \.todoKey) { item in
                            todoRow(item)
                        }
                    }
                }
            }
        }
        .padding(snap.overdueCount > 0 ? 10 : 0)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red.opacity(snap.overdueCount > 0 ? 0.06 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.red.opacity(snap.overdueCount > 0 ? 0.35 : 0), lineWidth: 1)
        )
    }

    private func countPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color))
    }

    private var quickAddRow: some View {
        HStack(spacing: 8) {
            TextField("Add a todo… (e.g. \u{201C}Send report tomorrow 3pm\u{201D})", text: $newTodoTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addTodo)
            Toggle(isOn: $newTodoHasDue) {
                Image(systemName: "bell")
            }
            .toggleStyle(.button)
            .help("Set a due time (fires a reminder notification)")
            if newTodoHasDue {
                DatePicker("", selection: $newTodoDue, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }
            Button("Add", action: addTodo)
                .disabled(newTodoTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.bottom, 2)
    }

    private func todoRow(_ item: DigestItem) -> some View {
        let isOverdue = item.priority >= 100
        return HStack(alignment: .top, spacing: 10) {
            Button {
                guard let id = item.externalID else { return }
                Task { await todos.complete(identifier: id) }
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .help("Mark complete")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.body).lineLimit(2)
                if let sub = item.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(isOverdue ? .red : .secondary)
                        .fontWeight(isOverdue ? .semibold : .regular)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let id = item.externalID {
                snoozeMenu(id: id)
            }
            priorityDot(item.priority)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isOverdue ? Color.red.opacity(0.10) : Color.secondary.opacity(0.08))
        )
        .contextMenu {
            if let id = item.externalID {
                Button("Complete") { Task { await todos.complete(identifier: id) } }
                Divider()
                snoozeButtons(id: id)
                Divider()
            }
            Button("Open Reminders") { RemindersFetcher.openRemindersApp() }
        }
    }

    private func snoozeMenu(id: String) -> some View {
        Menu {
            snoozeButtons(id: id)
        } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Snooze")
    }

    @ViewBuilder
    private func snoozeButtons(id: String) -> some View {
        ForEach(RemindersFetcher.SnoozeOption.allCases, id: \.self) { option in
            if let target = option.target() {
                Button(option.title) {
                    Task { await todos.snooze(identifier: id, until: target) }
                }
            }
        }
    }

    private func addTodo() {
        // An explicit due time wins; otherwise pick one out of the text ("…tomorrow 3pm").
        let parsed = newTodoHasDue
            ? TodoParser.Result(title: newTodoTitle.trimmingCharacters(in: .whitespaces), dueDate: newTodoDue)
            : TodoParser.parse(newTodoTitle)
        guard !parsed.title.isEmpty else { return }
        newTodoTitle = ""
        newTodoHasDue = false
        Task { await todos.add(title: parsed.title, dueDate: parsed.dueDate) }
    }

    private func relative(_ date: Date) -> String {
        Formatters.relative.localizedString(for: date, relativeTo: Date())
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

    private func reminderCard(_ reminder: Reminder) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sun.max.fill")
                .font(.body)
                .foregroundStyle(.orange)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(reminder.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let source = reminder.source {
                    Text("\u{2014} \(source)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            Button {
                coordinator.shuffleReminder()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.body)
            }
            .buttonStyle(.borderless)
            .help("Show a different reminder")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08))
        )
    }
}

private extension DigestItem {
    /// Stable row identity across refreshes (DigestItem.id is a fresh UUID each fetch),
    /// so completing one todo doesn't re-animate the whole list.
    var todoKey: String { externalID ?? id.uuidString }
}
