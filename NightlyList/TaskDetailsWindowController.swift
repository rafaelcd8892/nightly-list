import AppKit
import SwiftUI

/// La ventana de detalles de una tarea: notas, URL y prioridad.
///
/// Ventana y no un panel dentro del popover por dos razones. Escribir varias
/// lineas de notas en un popover que se cierra al perder el foco se pierde a
/// la primera; y asi la misma vista sirve desde Open, desde Hoy y desde la
/// ventana principal, sin repetirla tres veces.
@MainActor
final class TaskDetailsWindowController: NSObject {
    static let shared = TaskDetailsWindowController()

    private var window: NSWindow?

    func show(_ id: TodoItem.ID) {
        let window = self.window ?? makeWindow(for: id)
        self.window = window

        // La misma ventana se reutiliza para otra tarea: se le cambia el
        // contenido en vez de abrir una ventana por tarea.
        if let hosting = window.contentViewController as? NSHostingController<TaskDetailsView> {
            hosting.rootView = TaskDetailsView(id: id)
        }
        window.title = TaskStore.shared.item(id: id)?.title ?? "Task"

        // Una app LSUIElement no se pone delante sola.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(for id: TodoItem.ID) -> NSWindow {
        // Con la tarea de verdad desde el principio: la vista fija su tamaño y
        // una vacia dejaria la ventana con la medida del mensaje de error.
        let hosting = NSHostingController(rootView: TaskDetailsView(id: id))
        hosting.sizingOptions = [.preferredContentSize]

        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.setFrameAutosaveName("NightlyListTaskDetailsWindow")
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
