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
                .tabItem { Label("Sincronización", systemImage: "arrow.triangle.2.circlepath") }

            DiagnosticSettingsTab()
                .tabItem { Label("Diagnóstico", systemImage: "stethoscope") }
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
                Toggle("Abrir Recordatorios al iniciar sesión", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginError = loginItem.setEnabled($0) }
                ))

                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("También puedes cambiarlo en Ajustes del Sistema › General › Ítems de inicio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Atajo") {
                LabeledContent("Captura rápida", value: "⌥ Espacio")
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
                Toggle("Sincronizar con la app Recordatorios", isOn: Binding(
                    get: { sync.isSyncEnabled },
                    set: setEnabled
                ))
            } footer: {
                Text("Tus tareas se guardan como recordatorios de Apple, así que llegan al iPhone y al iPad por iCloud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if sync.isSyncEnabled {
                Section("Estado") {
                    LabeledContent("Última sincronización") {
                        if let lastSync = sync.lastSyncDate {
                            Text(lastSync, style: .relative)
                        } else {
                            Text("nunca").foregroundStyle(.secondary)
                        }
                    }

                    Button("Sincronizar ahora") {
                        Task { await sync.performFullSync() }
                    }
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
            DiagnosticLog.shared.log(.sync, "Sincronizacion desactivada")
            return
        }
        Task {
            let granted = await sync.requestAuthorization()
            sync.isSyncEnabled = granted
            DiagnosticLog.shared.log(.sync, granted
                ? "Sincronizacion activada"
                : "Sincronizacion rechazada: sin permiso de Recordatorios")
            if granted { await sync.performFullSync() }
        }
    }
}

// MARK: - Diagnostico

private struct DiagnosticSettingsTab: View {
    @StateObject private var log = DiagnosticLog.shared
    @State private var contents = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Registro de lo que hace la app. Útil para entender un fallo de sincronización o de guardado.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(contents.isEmpty ? "El registro está vacío." : contents)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))

            HStack {
                Button("Copiar") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(contents, forType: .string)
                }
                .disabled(contents.isEmpty)

                Button("Mostrar en el Finder") {
                    guard let fileURL = log.fileURL else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
                .disabled(log.fileURL == nil)

                Spacer()

                Button("Vaciar", role: .destructive) {
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
