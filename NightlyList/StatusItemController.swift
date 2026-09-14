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

    /// Los vigilantes del clic fuera, solo mientras el popover esta abierto.
    private var outsideClickMonitors: [Any] = []

    init(store: TaskStore) {
        self.store = store
        super.init()

        // .applicationDefined y no .transient: el cierre lo decide esta clase.
        // Un popover transitorio que se abre sin activar la app depende de que
        // el sistema le de el foco para saber cuando se pincho fuera, y sin
        // foco ese cierre no llega. Los monitores de abajo lo hacen explicito.
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: TaskListView(store: store))

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(buttonClicked)
            // Sin esto solo llega el clic izquierdo y el derecho se pierde.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Abrir Ajustes o los detalles desde el propio popover no genera
        // ningun clic fuera, asi que sin esto el popover se quedaba flotando
        // por delante de la ventana que acababa de abrir.
        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let self, self.popover.isShown else { return }
                guard note.object as? NSWindow !== self.popover.contentViewController?.view.window
                else { return }
                self.popover.performClose(nil)
            }
            .store(in: &cancellables)

        refreshImage()
        // El numero del icono tiene que seguir a la lista.
        store.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshImage() }
            .store(in: &cancellables)
    }

    /// @objc explicito: popoverDidClose es un metodo opcional de un protocolo
    /// de ObjC, y sin la marca el runtime no lo encuentra.
    @objc nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            self.stopWatchingForOutsideClicks()
            PopoverSession.shared.didClose()
        }
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

        // Sin NSApp.activate: abrir la lista no tiene por que sacar de la
        // ventana en la que estabas. La app se queda de fondo y el Xcode, el
        // navegador o lo que fuera conserva el foco y el cursor donde estaba.
        //
        // El precio es que el campo "New task" no recibe teclas hasta que se
        // pincha dentro, porque una app inactiva no recibe el teclado. Pinchar
        // dentro activa la app sola, asi que el coste real es un clic, y solo
        // cuando se va a escribir. Para escribir sin tocar el raton esta el
        // atajo, que si activa la app a proposito.
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startWatchingForOutsideClicks()
    }

    // MARK: - Cerrar al pinchar fuera

    /// Cierra el popover al primer clic fuera, dentro o fuera de esta app.
    ///
    /// El monitor global recoge los clics que van a otras apps; el local, los
    /// que van a otra ventana de esta. Los del propio icono de la barra no
    /// cuentan: de esos ya se encarga togglePopover, y cerrar aqui haria que
    /// el clic siguiente lo volviera a abrir.
    private func startWatchingForOutsideClicks() {
        stopWatchingForOutsideClicks()

        let buttons: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: buttons) { [weak self] _ in
            Task { @MainActor in self?.popover.performClose(nil) }
        } {
            outsideClickMonitors.append(global)
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: buttons) { [weak self] event in
            guard let self else { return event }
            let popoverWindow = self.popover.contentViewController?.view.window
            let statusWindow = self.statusItem.button?.window

            if event.window !== popoverWindow, event.window !== statusWindow {
                Task { @MainActor in self.popover.performClose(nil) }
            }
            return event
        } {
            outsideClickMonitors.append(local)
        }
    }

    private func stopWatchingForOutsideClicks() {
        outsideClickMonitors.forEach(NSEvent.removeMonitor)
        outsideClickMonitors.removeAll()
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

    // MARK: - Acciones del menu

    @objc private func openMainWindow() {
        MainWindowController.shared.show()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
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
