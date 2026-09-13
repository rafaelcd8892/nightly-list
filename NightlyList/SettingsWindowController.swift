import AppKit
import SwiftUI

/// La ventana de Ajustes, gestionada con AppKit.
///
/// Era una escena Settings de SwiftUI, y desde el menu del icono no habia
/// forma de abrirla: la accion se entregaba (sendAction devolvia true) y la
/// escena creaba una ventana sin titulo que nunca llegaba a mostrarse, una mas
/// en cada intento. Con la ventana propia no hay selector privado que adivinar,
/// ni escena que dependa del contexto desde el que se invoca.
@MainActor
final class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window

        // Una app LSUIElement no se pone delante sola.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Nightly List Settings"
        window.contentViewController = NSHostingController(rootView: SettingsView())
        window.setFrameAutosaveName("NightlyListSettingsWindow")
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
