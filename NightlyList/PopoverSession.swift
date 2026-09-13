import Combine
import Foundation

/// Avisa a la interfaz de que el popover se ha cerrado.
///
/// Hace falta porque el popover no se destruye: su NSHostingController se crea
/// una vez y se reutiliza, asi que onDisappear no llega nunca y cualquier
/// estado a medias (una fila en modo renombrar) sobrevive a cerrarlo y volver
/// a abrirlo.
@MainActor
final class PopoverSession: ObservableObject {
    static let shared = PopoverSession()

    /// Sube cada vez que el popover se cierra.
    @Published private(set) var closeCount = 0

    func didClose() {
        closeCount += 1
    }
}
