import SwiftUI

/// La ventanita de captura rapida que abre el atajo global.
///
/// Es un NSPanel y no una escena de SwiftUI porque hay que abrirlo desde el
/// handler del atajo, fuera de cualquier jerarquia de vistas.
@MainActor
final class QuickAddPanel {
    private var panel: NSPanel?

    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            show()
        }
    }

    private func show() {
        // Panel nuevo en cada apertura: reutilizarlo no vuelve a disparar el
        // onAppear de la vista, y sin el el campo no recupera el foco a la
        // segunda vez que se abre.
        let panel = makePanel()
        self.panel = panel

        panel.center()
        // Un poco por encima del centro: es donde el ojo ya esta mirando.
        if let screen = panel.screen ?? NSScreen.main {
            var frame = panel.frame
            frame.origin.y = screen.visibleFrame.midY + screen.visibleFrame.height * 0.12
            panel.setFrameOrigin(frame.origin)
        }

        // Una app LSUIElement no es activa por defecto y el campo no
        // recibiria teclas.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 64),
            // Sin .nonactivatingPanel: con esa mascara el panel nunca llega a
            // ser ventana clave y el campo no recibe las pulsaciones.
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        panel.contentView = NSHostingView(
            rootView: QuickAddView(store: .shared) { [weak self] in self?.close() }
        )
        return panel
    }
}

private struct QuickAddView: View {
    @ObservedObject var store: TaskStore
    @State private var title = ""
    @FocusState private var focused: Bool
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)

            TextField("Nueva tarea…", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($focused)
                .onSubmit { save(alreadyDone: false) }

            Text("⌘⏎ hecha")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            // Un boton oculto es la forma de colgar un atajo de teclado de
            // una accion que no tiene sitio en la interfaz.
            Button("") { save(alreadyDone: true) }
                .keyboardShortcut(.return, modifiers: .command)
                .hidden()
                .frame(width: 0, height: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 460)
        .onExitCommand(perform: onClose)
        .onAppear { focused = true }
    }

    /// alreadyDone distingue las dos formas de cerrar el panel: Enter apunta
    /// una tarea pendiente, ⌘Enter registra algo que ya esta hecho.
    private func save(alreadyDone: Bool) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onClose()
            return
        }

        if alreadyDone {
            store.addCompleted(trimmed)
        } else {
            store.add(trimmed)
        }

        title = ""
        onClose()
    }
}
