import Carbon.HIToolbox
import Combine
import Foundation

/// El atajo global de la captura rapida, guardado entre sesiones.
struct QuickCaptureShortcut: Equatable, Codable {
    /// Un kVK_*.
    var keyCode: UInt32
    /// Mascara de Carbon: cmdKey, optionKey, controlKey, shiftKey.
    var carbonModifiers: UInt32
    /// Como se escribe, calculado al capturarlo.
    var display: String

    /// Control+Opcion+Comando+N.
    ///
    /// Tres modificadores a proposito: las combinaciones de dos las tiene
    /// cogidas medio sistema. ⌥Espacio se la llevan los lanzadores, y ⌃Espacio
    /// y ⌃⌥Espacio son el cambio de idioma de macOS.
    static let fallback = QuickCaptureShortcut(
        keyCode: UInt32(kVK_ANSI_N),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
        display: "⌃⌥⌘N"
    )

    private static let defaultsKey = "quickCapture.shortcut"

    static var current: QuickCaptureShortcut {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode(QuickCaptureShortcut.self, from: data)
        else { return fallback }
        return stored
    }

    static func save(_ shortcut: QuickCaptureShortcut) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

/// Registra el atajo guardado y lo vuelve a registrar cuando cambia.
@MainActor
final class QuickCaptureHotKey: ObservableObject {
    static let shared = QuickCaptureHotKey()

    /// true si el sistema rechazo la ultima combinacion, normalmente porque
    /// otra app ya la tiene cogida.
    @Published private(set) var isTaken = false

    private var action: (() -> Void)?

    func start(action: @escaping () -> Void) {
        self.action = action
        apply()
    }

    func apply() {
        guard let action else { return }

        HotKeyCenter.shared.unregisterAll()
        let shortcut = QuickCaptureShortcut.current
        let registrado = HotKeyCenter.shared.register(
            keyCode: shortcut.keyCode,
            modifiers: shortcut.carbonModifiers,
            action: action
        )
        isTaken = !registrado

        DiagnosticLog.shared.log(
            .app,
            registrado
                ? "Quick capture bound to \(shortcut.display)"
                : "\(shortcut.display) is already taken by another app"
        )
    }
}
