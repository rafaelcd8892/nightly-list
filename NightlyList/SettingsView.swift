import SwiftUI

/// La ventana de Ajustes (⌘,).
///
/// Aqui viven las opciones que antes colgaban del popover. El popover es la
/// vista rapida; todo lo que se toca una vez y se olvida va aqui.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            SyncSettingsTab()
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }

            SummarySettingsTab()
                .tabItem { Label("Summary", systemImage: "text.quote") }

            DiagnosticSettingsTab()
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
        }
        .frame(width: 480, height: 360)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @StateObject private var loginItem = LoginItem()
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginError = loginItem.setEnabled($0) }
                ))

                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("You can also change this in System Settings › General › Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Shortcut") {
                LabeledContent("Quick capture", value: "⌥ Space")
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refresh() }
    }
}

// MARK: - Sincronizacion

private struct SyncSettingsTab: View {
    @StateObject private var sync = RemindersSync.shared

    var body: some View {
        Form {
            Section {
                Toggle("Sync with Apple Reminders", isOn: Binding(
                    get: { sync.isSyncEnabled },
                    set: setEnabled
                ))
            } footer: {
                Text("Your tasks are stored as Apple reminders, so they reach your iPhone and iPad through iCloud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if sync.isSyncEnabled {
                Section("Status") {
                    LabeledContent("Last sync") {
                        if let lastSync = sync.lastSyncDate {
                            Text(lastSync, style: .relative)
                        } else {
                            Text("never").foregroundStyle(.secondary)
                        }
                    }

                    Button("Sync now") {
                        Task { await sync.performFullSync() }
                    }
                }
            }

            if sync.isSyncEnabled && !sync.lists.isEmpty {
                Section {
                    ForEach(sync.lists) { list in
                        Toggle(isOn: Binding(
                            get: { sync.isEnabled(list) },
                            set: { sync.setList(list, enabled: $0) }
                        )) {
                            Label {
                                Text(list.title)
                            } icon: {
                                Image(systemName: "circle.fill").foregroundStyle(list.color)
                            }
                        }
                    }
                } header: {
                    Text("Lists to sync")
                } footer: {
                    Text("Turning a list off removes its tasks from here. They stay in Reminders and come back if you turn it on again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = sync.lastSyncError {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setEnabled(_ enabled: Bool) {
        guard enabled else {
            sync.isSyncEnabled = false
            DiagnosticLog.shared.log(.sync, "Sync turned off")
            return
        }
        Task {
            let granted = await sync.requestAuthorization()
            sync.isSyncEnabled = granted
            DiagnosticLog.shared.log(.sync, granted
                ? "Sync turned on"
                : "Sync refused: no Reminders permission")
            if granted { await sync.performFullSync() }
        }
    }
}

// MARK: - Resumen del dia

private struct SummarySettingsTab: View {
    @State private var draft = SummaryPrompt.current

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This text is appended to the exported day, so you can hand it to a model without retyping it every time.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $draft)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 160)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.quaternary)
                )

            HStack {
                Button("Reset") {
                    SummaryPrompt.reset()
                    draft = SummaryPrompt.defaultText
                }
                .disabled(draft == SummaryPrompt.defaultText)

                Spacer()

                Text(saved ? "Saved" : "Unsaved")
                    .font(.caption)
                    .foregroundStyle(saved ? Color.secondary : Color.orange)

                Button("Save") { SummaryPrompt.save(draft) }
                    .keyboardShortcut("s")
                    .disabled(saved)
            }
        }
        .padding(16)
    }

    private var saved: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines) == SummaryPrompt.current
    }
}

// MARK: - Diagnostico

private struct DiagnosticSettingsTab: View {
    @StateObject private var log = DiagnosticLog.shared
    @State private var contents = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A record of what the app does. Useful for tracking down a sync or save failure.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(contents.isEmpty ? "The log is empty." : contents)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))

            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(contents, forType: .string)
                }
                .disabled(contents.isEmpty)

                Button("Show in Finder") {
                    guard let fileURL = log.fileURL else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
                .disabled(log.fileURL == nil)

                Spacer()

                Button("Clear", role: .destructive) {
                    log.clear()
                }
                .disabled(contents.isEmpty)
            }
        }
        .padding(16)
        .onAppear { contents = log.readAll() }
        // revision cambia con cada linea escrita y con el vaciado.
        .onChange(of: log.revision) { _, _ in contents = log.readAll() }
    }
}
