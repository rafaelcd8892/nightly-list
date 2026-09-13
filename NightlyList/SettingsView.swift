import SwiftUI

/// La ventana de Ajustes.
///
/// Aqui viven las opciones que antes colgaban del popover. El popover es la
/// vista rapida; todo lo que se toca una vez y se olvida va aqui.
///
/// El selector es un Picker y no un TabView a proposito: dentro de una ventana
/// propia, un TabView se lleva las pestañas a la barra de titulo y las colapsa
/// en un boton de desbordamiento. Eso solo sale bien dentro de la escena
/// Settings de SwiftUI, que es justo la que no podiamos usar.
struct SettingsView: View {
    @State private var section: Section = .general

    enum Section: String, CaseIterable, Identifiable {
        case general = "General"
        case sync = "Sync"
        case summary = "Summary"
        case diagnostics = "Diagnostics"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .sync: return "arrow.triangle.2.circlepath"
            case .summary: return "text.quote"
            case .diagnostics: return "stethoscope"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $section) {
                ForEach(Section.allCases) { section in
                    Label(section.rawValue, systemImage: section.symbol).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            Group {
                switch section {
                case .general: GeneralSettingsTab()
                case .sync: SyncSettingsTab()
                case .summary: SummarySettingsTab()
                case .diagnostics: DiagnosticSettingsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 520, height: 420)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @StateObject private var loginItem = LoginItem()
    @StateObject private var hotKey = QuickCaptureHotKey.shared
    @State private var loginError: String?
    @State private var shortcut = QuickCaptureShortcut.current
    @State private var recording = false

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

            Section {
                LabeledContent("Quick capture") {
                    HStack(spacing: 8) {
                        if recording {
                            Text("Press a combination…")
                                .foregroundStyle(.secondary)
                            ShortcutRecorder { capturado in
                                QuickCaptureShortcut.save(capturado)
                                shortcut = capturado
                                recording = false
                                hotKey.apply()
                            }
                            .frame(width: 1, height: 1)
                        } else {
                            Text(shortcut.display)
                                .font(.system(.body, design: .monospaced))
                        }

                        Button(recording ? "Cancel" : "Change") {
                            recording.toggle()
                        }

                        Button("Reset") {
                            QuickCaptureShortcut.reset()
                            shortcut = QuickCaptureShortcut.current
                            recording = false
                            hotKey.apply()
                        }
                        .disabled(shortcut == QuickCaptureShortcut.fallback)
                    }
                }

                if hotKey.isTaken {
                    Text("Another app already uses \(shortcut.display). Pick a different one.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Shortcut")
            } footer: {
                Text("Opens the quick capture panel from anywhere. Enter saves the task; ⌘↩ records something you already finished.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
