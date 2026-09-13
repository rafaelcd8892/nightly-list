import AppKit
import SwiftUI

/// La ventana principal, gestionada con AppKit.
///
/// No es una escena Window de SwiftUI porque hay que abrirla desde sitios que
/// no son vistas: el menu del clic derecho sobre el icono de la barra. La
/// accion openWindow del entorno solo existe dentro de una vista, y depender de
/// que el popover se haya abierto antes para capturarla es fragil.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

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
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Nightly List"
        window.contentViewController = NSHostingController(rootView: MainWindowView(store: .shared))
        window.setFrameAutosaveName("NightlyListMainWindow")
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        return window
    }
}
