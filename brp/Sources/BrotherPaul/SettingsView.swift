import SwiftUI

struct SettingsView: View {
    @State private var config: AppConfig = ConfigManager.shared.config
    @State private var selectedModeID: LaunchMode.ID?
    @State private var newAppName: String = ""
    @State private var saveError: String?

    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(alignment: .top, spacing: 16) {
                modeList
                modeEditor
            }

            globalSettings

            footer
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 480)
        .onAppear {
            selectedModeID = config.modes.first?.id
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Brother Paul").font(.title2).bold()
                Text("Start your work with one command.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var modeList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Modes").font(.headline)
            List(selection: $selectedModeID) {
                ForEach(config.modes) { mode in
                    Text(mode.name).tag(Optional(mode.id))
                }
                .onDelete(perform: deleteModes)
            }
            .frame(minWidth: 160, minHeight: 200)

            HStack {
                Button {
                    addMode()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                Button {
                    if let id = selectedModeID {
                        config.modes.removeAll { $0.id == id }
                        selectedModeID = config.modes.first?.id
                    }
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .disabled(selectedModeID == nil || config.modes.count <= 1)
            }
        }
    }

    private var modeEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let index = currentIndex {
                Text("Apps in \(config.modes[index].name)").font(.headline)

                TextField("Mode name", text: Binding(
                    get: { config.modes[index].name },
                    set: { config.modes[index].name = $0 }
                ))

                List {
                    ForEach(config.modes[index].apps, id: \.self) { app in
                        Text(app)
                    }
                    .onDelete { offsets in
                        config.modes[index].apps.remove(atOffsets: offsets)
                    }
                }
                .frame(minHeight: 160)

                HStack {
                    TextField("App name (e.g. Slack)", text: $newAppName)
                        .onSubmit(addApp)
                    Button("Add", action: addApp)
                        .disabled(newAppName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Text("Select a mode to edit").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var globalSettings: some View {
        GroupBox("Global") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Hide other apps after launch", isOn: $config.hideOthersAfterLaunch)

                Picker("Default mode", selection: $config.defaultMode) {
                    ForEach(config.modes) { mode in
                        Text(mode.name).tag(mode.name)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.vertical, 4)
        }
    }

    private var footer: some View {
        HStack {
            if let saveError = saveError {
                Text(saveError).foregroundStyle(.red).font(.caption)
            }
            Spacer()
            Button("Open config.json") {
                NSWorkspace.shared.open(ConfigManager.shared.configFile)
            }
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
        }
    }

    private var currentIndex: Int? {
        guard let id = selectedModeID else { return nil }
        return config.modes.firstIndex { $0.id == id }
    }

    private func addMode() {
        let baseName = "New Mode"
        var name = baseName
        var counter = 2
        let existing = Set(config.modes.map { $0.name })
        while existing.contains(name) {
            name = "\(baseName) \(counter)"
            counter += 1
        }
        let mode = LaunchMode(name: name, apps: [])
        config.modes.append(mode)
        selectedModeID = mode.id
    }

    private func deleteModes(at offsets: IndexSet) {
        config.modes.remove(atOffsets: offsets)
        selectedModeID = config.modes.first?.id
    }

    private func addApp() {
        guard let index = currentIndex else { return }
        let trimmed = newAppName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        config.modes[index].apps.append(trimmed)
        newAppName = ""
    }

    private func save() {
        do {
            try ConfigManager.shared.write(config)
            saveError = nil
            onSave()
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
        }
    }
}
