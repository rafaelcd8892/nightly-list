import AppKit
import Combine
import SwiftUI

/// El icono de la barra de menus y su popover.
///
/// Se gestiona con NSStatusItem y no con MenuBarExtra porque este ultimo no
/// distingue el boton del raton: abre su popover con cualquier clic y no deja
/// poner un menu contextual. Con el status item a mano, el clic izquierdo abre
/// el popover y el derecho abre el menu.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let store: TaskStore
    private var cancellables: Set<AnyCancellable> = []

    init(store: TaskStore) {
        self.store = store
        super.init()

        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: TaskListView(store: store))

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(buttonClicked)
            // Sin esto solo llega el clic izquierdo y el derecho se pierde.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        refreshImage()
        // El numero del icono tiene que seguir a la lista.
        store.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshImage() }
            .store(in: &cancellables)
    }

    // MARK: - Clics

    @objc private func buttonClicked() {
        let esDerecho = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true

        if esDerecho {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        // El campo de texto del popover no recibe teclas si la app no esta
        // activa, y una app LSUIElement no se activa sola.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func showMenu() {
        // El popover se queda abierto detras del menu si no se cierra a mano:
        // el menu no le roba el foco de la forma que dispara su cierre
        // automatico.
        if popover.isShown {
            popover.performClose(nil)
        }

        let menu = NSMenu()

        menu.addItem(item("Main Window…", #selector(openMainWindow)))
        menu.addItem(item("Settings…", #selector(openSettings)))
        menu.addItem(.separator())

        let archivar = item("Archive \(doneCount) completed", #selector(archiveDone))
        archivar.isEnabled = doneCount > 0
        menu.addItem(archivar)

        menu.addItem(.separator())
        menu.addItem(item("Quit", #selector(quit), key: "q"))

        // Asignar el menu al status item haria que el clic izquierdo tambien lo
        // abriera. Se ensena a mano y se retira en cuanto se cierra.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    private var doneCount: Int {
        store.items.count { $0.isDone }
    }

    // MARK: - Acciones del menu

    @objc private func openMainWindow() {
        MainWindowController.shared.show()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)

        // sendAction recorre la cadena de respondedores. responds(to:) solo
        // pregunta a NSApplication, y la accion de Ajustes no vive ahi: por eso
        // no abria desde el menu mientras el SettingsLink del popover si.
        // El selector cambio de nombre en macOS 14, se prueban los dos.
        for selector in [Selector(("showSettingsWindow:")), Selector(("showPreferencesWindow:"))]
        where NSApp.sendAction(selector, to: nil, from: nil) {
            return
        }

        DiagnosticLog.shared.log(.app, "Could not open Settings from the status item menu")
    }

    @objc private func archiveDone() {
        store.clearDone()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Icono

    private func refreshImage() {
        statusItem.button?.image = Self.statusImage(pending: store.pendingCount)
    }

    /// Icono y numero juntos hay que rasterizarlos: la barra de menus acepta
    /// una imagen, no una vista.
    private static func statusImage(pending: Int) -> NSImage {
        let label = HStack(spacing: 3) {
            Image(systemName: "checklist")
            Text("\(pending)")
                .font(.system(size: 12, weight: .semibold))
        }
        .frame(height: 16)

        let renderer = ImageRenderer(content: label)
        renderer.scale = 2

        guard let image = renderer.nsImage else {
            return NSImage(systemSymbolName: "checklist", accessibilityDescription: nil) ?? NSImage()
        }
        // Plantilla: el sistema lo recolorea segun la barra clara u oscura.
        image.isTemplate = true
        return image
    }
}
