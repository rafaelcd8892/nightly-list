import UserNotifications

/// Programa una notificacion local por cada tarea pendiente con fecha futura.
///
/// El identificador de cada notificacion es el UUID de la tarea, asi que
/// reprogramar y cancelar son idempotentes: basta con volver a sincronizar.
@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    /// Pide permiso solo cuando hace falta: la primera vez que una tarea
    /// recibe fecha. Devuelve false si el usuario lo tiene denegado.
    @discardableResult
    func ensureAuthorized() async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }

    /// Deja programadas exactamente las tareas pendientes con fecha futura y
    /// retira las demas (hechas, borradas, sin fecha o ya pasadas).
    func sync(_ items: [TodoItem]) {
        Task { await syncNow(items) }
    }

    private func syncNow(_ items: [TodoItem]) async {
        let wanted = items.filter { !$0.isDone && ($0.dueDate ?? .distantPast) > .now }
        let wantedIDs = Set(wanted.map(\.id.uuidString))

        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { !wantedIDs.contains($0) }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
            DiagnosticLog.shared.log(.notifications, "Retirados \(stale.count) avisos que ya no tocan")
        }

        for item in wanted {
            guard let dueDate = item.dueDate else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Recordatorio"
            content.body = item.title
            content.sound = .default

            // Con granularidad de minuto, una fecha a las 21:47:30 se
            // programaria para 21:47:00 (ya pasado) y no llegaria nunca.
            let fields = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: dueDate
            )
            let request = UNNotificationRequest(
                identifier: item.id.uuidString,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: fields, repeats: false)
            )
            do {
                try await center.add(request)
            } catch {
                DiagnosticLog.shared.log(
                    .notifications,
                    "No se pudo programar \"\(item.title)\": \(error.localizedDescription)"
                )
            }
        }

    }
}
