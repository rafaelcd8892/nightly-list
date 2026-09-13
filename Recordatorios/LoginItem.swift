import Combine
import ServiceManagement

/// Envuelve SMAppService para poder atarlo a un Toggle.
///
/// El usuario tambien puede cambiarlo desde Ajustes del Sistema > General >
/// Items de inicio, asi que hay que releer el estado al abrir el popover.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled = false

    init() { refresh() }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Devuelve el mensaje de error si el sistema rechaza el cambio, o nil.
    func setEnabled(_ enabled: Bool) -> String? {
        defer { refresh() }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            DiagnosticLog.shared.log(.login, enabled
                ? "Registrado para abrir al iniciar sesion"
                : "Ya no abre al iniciar sesion")
            return nil
        } catch {
            DiagnosticLog.shared.log(.login, "Fallo al cambiarlo: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }
}
