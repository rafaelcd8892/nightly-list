import EventKit
import Foundation
import Combine

/// Gestiona la sincronizacion bidireccional entre las tareas de la app y
/// los recordatorios de la app Recordatorios de Apple.
@MainActor
final class RemindersSync: ObservableObject {
    static let shared = RemindersSync()
    
    private let eventStore = EKEventStore()
    
    /// Estado de autorizacion para acceder a los recordatorios.
    @Published private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    
    /// Si la sincronizacion esta activada por el usuario.
    @Published var isSyncEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isSyncEnabled, forKey: syncEnabledKey)
            if isSyncEnabled {
                Task { await performFullSync() }
            }
        }
    }
    
    /// Errores de sincronizacion para mostrar en la UI.
    @Published var lastSyncError: String?
    
    /// Ultima vez que se sincronizo correctamente.
    @Published var lastSyncDate: Date?
    
    private let syncEnabledKey = "reminders.sync.enabled"
    private let lastSyncKey = "reminders.sync.lastDate"
    
    private init() {
        self.authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        self.isSyncEnabled = UserDefaults.standard.bool(forKey: syncEnabledKey)
        
        if let timestamp = UserDefaults.standard.object(forKey: lastSyncKey) as? Date {
            self.lastSyncDate = timestamp
        }
        
        // Observar cambios externos en la app Recordatorios
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExternalChange),
            name: .EKEventStoreChanged,
            object: eventStore
        )
    }
    
    // MARK: - Authorization
    
    /// Pide permiso al usuario para acceder a sus recordatorios.
    func requestAuthorization() async -> Bool {
        do {
            // Para macOS 14+ y iOS 17+
            if #available(macOS 14.0, iOS 17.0, *) {
                let granted = try await eventStore.requestFullAccessToReminders()
                await MainActor.run {
                    self.authorizationStatus = granted ? .fullAccess : .denied
                }
                return granted
            } else {
                // Fallback para versiones anteriores
                return await withCheckedContinuation { continuation in
                    eventStore.requestAccess(to: .reminder) { granted, error in
                        Task { @MainActor in
                            self.authorizationStatus = granted ? .fullAccess : .denied
                            if let error = error {
                                self.lastSyncError = "Error al solicitar permisos: \(error.localizedDescription)"
                            }
                            continuation.resume(returning: granted)
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.authorizationStatus = .denied
                self.lastSyncError = "Error al solicitar permisos: \(error.localizedDescription)"
            }
            return false
        }
    }
    
    /// Comprueba si tenemos permiso antes de sincronizar.
    private func ensureAuthorized() async -> Bool {
        let status = authorizationStatus
        
        // Manejar ambos .authorized (antiguo) y .fullAccess (nuevo)
        if status == .fullAccess || status == .authorized {
            return true
        }
        
        if status == .notDetermined {
            return await requestAuthorization()
        }
        
        lastSyncError = "Permisos denegados. Actívalos en Ajustes del Sistema."
        return false
    }
    
    // MARK: - Sync Operations
    
    /// Sincronizacion completa bidireccional.
    /// 1. Sube tareas locales que no esten en Recordatorios
    /// 2. Baja recordatorios que no esten en local
    /// 3. Actualiza los que existen en ambos lados
    func performFullSync() async {
        guard isSyncEnabled else { return }
        guard await ensureAuthorized() else { return }
        
        do {
            // 1. Obtener todos los recordatorios de la app Recordatorios
            let predicate = eventStore.predicateForReminders(in: [defaultCalendar()])
            let reminders = try await fetchReminders(matching: predicate)
            
            // 2. Obtener todas las tareas locales
            let localItems = TaskStore.shared.items
            
            // 3. Crear mapas para comparacion rapida
            let remindersByID = Dictionary(
                uniqueKeysWithValues: reminders.map { ($0.calendarItemIdentifier, $0) }
            )
            let localItemsByReminderID = Dictionary(
                uniqueKeysWithValues: localItems
                    .compactMap { item -> (String, TodoItem)? in
                        guard let reminderID = item.reminderIdentifier else { return nil }
                        return (reminderID, item)
                    }
            )
            
            // 4. Sincronizar en ambas direcciones
            try await syncLocalToReminders(localItems, remindersByID: remindersByID)
            try await syncRemindersToLocal(reminders, localItemsByReminderID: localItemsByReminderID)
            
            // 5. Actualizar estado
            lastSyncError = nil
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)
            
        } catch {
            lastSyncError = "Error en sincronización: \(error.localizedDescription)"
        }
    }
    
    /// Envuelve el API de completion handler de EventKit en async/await.
    private func fetchReminders(matching predicate: NSPredicate) async throws -> [EKReminder] {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                if let reminders = reminders {
                    continuation.resume(returning: reminders)
                } else {
                    continuation.resume(throwing: SyncError.reminderNotFound)
                }
            }
        }
    }
    
    /// Sube tareas locales a Recordatorios (crea nuevas o actualiza existentes).
    private func syncLocalToReminders(
        _ localItems: [TodoItem],
        remindersByID: [String: EKReminder]
    ) async throws {
        for item in localItems {
            if let reminderID = item.reminderIdentifier,
               let existingReminder = remindersByID[reminderID] {
                // Actualizar recordatorio existente si la tarea local es mas reciente
                if shouldUpdateReminder(existingReminder, with: item) {
                    try updateReminder(existingReminder, from: item)
                }
            } else {
                // Crear nuevo recordatorio
                let reminderID = try await createReminder(from: item)
                updateLocalItem(item, withReminderID: reminderID)
            }
        }
    }
    
    /// Baja recordatorios de la app Recordatorios a local (crea nuevas o actualiza existentes).
    private func syncRemindersToLocal(
        _ reminders: [EKReminder],
        localItemsByReminderID: [String: TodoItem]
    ) async throws {
        for reminder in reminders {
            let reminderID = reminder.calendarItemIdentifier
            
            if let existingItem = localItemsByReminderID[reminderID] {
                // Actualizar tarea local si el recordatorio es mas reciente
                if shouldUpdateLocalItem(existingItem, with: reminder) {
                    updateLocalItem(from: reminder)
                }
            } else {
                // Crear nueva tarea local desde recordatorio
                createLocalItem(from: reminder)
            }
        }
    }
    
    // MARK: - Individual Operations
    
    /// Crea un recordatorio en la app Recordatorios desde una tarea local.
    @discardableResult
    func createReminder(from item: TodoItem) async throws -> String {
        guard await ensureAuthorized() else {
            throw SyncError.unauthorized
        }
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = item.title
        reminder.isCompleted = item.isDone
        reminder.calendar = defaultCalendar()
        
        if let dueDate = item.dueDate {
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
            reminder.dueDateComponents = components
            
            // Crear alarma para la fecha de vencimiento
            let alarm = EKAlarm(absoluteDate: dueDate)
            reminder.addAlarm(alarm)
        }
        
        // Guardar en la app Recordatorios
        try eventStore.save(reminder, commit: true)
        
        return reminder.calendarItemIdentifier
    }
    
    /// Actualiza un recordatorio existente con los datos de una tarea local.
    func updateReminder(_ reminder: EKReminder, from item: TodoItem) throws {
        reminder.title = item.title
        reminder.isCompleted = item.isDone
        
        if let dueDate = item.dueDate {
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
            reminder.dueDateComponents = components
            
            // Actualizar o crear alarma
            if reminder.alarms?.isEmpty ?? true {
                let alarm = EKAlarm(absoluteDate: dueDate)
                reminder.addAlarm(alarm)
            } else if let alarm = reminder.alarms?.first {
                alarm.absoluteDate = dueDate
            }
        } else {
            reminder.dueDateComponents = nil
            reminder.alarms?.forEach { reminder.removeAlarm($0) }
        }
        
        try eventStore.save(reminder, commit: true)
    }
    
    /// Elimina un recordatorio de la app Recordatorios.
    func deleteReminder(withID reminderID: String) throws {
        guard let reminder = eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            return // Ya no existe
        }
        try eventStore.remove(reminder, commit: true)
    }
    
    /// Crea una tarea local desde un recordatorio de la app Recordatorios.
    private func createLocalItem(from reminder: EKReminder) {
        var item = TodoItem(
            title: reminder.title ?? "Sin título",
            isDone: reminder.isCompleted
        )
        
        if let dueDateComponents = reminder.dueDateComponents,
           let dueDate = Calendar.current.date(from: dueDateComponents) {
            item.dueDate = dueDate
        }
        
        item.reminderIdentifier = reminder.calendarItemIdentifier
        item.lastModified = reminder.lastModifiedDate ?? Date()
        
        TaskStore.shared.items.append(item)
    }
    
    /// Actualiza una tarea local existente con datos de un recordatorio.
    private func updateLocalItem(from reminder: EKReminder) {
        guard let index = TaskStore.shared.items.firstIndex(where: {
            $0.reminderIdentifier == reminder.calendarItemIdentifier
        }) else { return }
        
        var item = TaskStore.shared.items[index]
        item.title = reminder.title ?? item.title
        item.isDone = reminder.isCompleted
        
        if let dueDateComponents = reminder.dueDateComponents,
           let dueDate = Calendar.current.date(from: dueDateComponents) {
            item.dueDate = dueDate
        } else {
            item.dueDate = nil
        }
        
        item.lastModified = reminder.lastModifiedDate ?? Date()
        
        TaskStore.shared.items[index] = item
    }
    
    /// Actualiza una tarea local con el ID del recordatorio tras crearlo.
    private func updateLocalItem(_ item: TodoItem, withReminderID reminderID: String) {
        guard let index = TaskStore.shared.items.firstIndex(where: { $0.id == item.id }) else {
            return
        }
        
        var updatedItem = TaskStore.shared.items[index]
        updatedItem.reminderIdentifier = reminderID
        TaskStore.shared.items[index] = updatedItem
    }
    
    // MARK: - Conflict Resolution
    
    /// Decide si hay que actualizar un recordatorio basandose en las fechas de modificacion.
    private func shouldUpdateReminder(_ reminder: EKReminder, with item: TodoItem) -> Bool {
        let reminderModified = reminder.lastModifiedDate ?? .distantPast
        return item.lastModified > reminderModified
    }
    
    /// Decide si hay que actualizar una tarea local basandose en las fechas de modificacion.
    private func shouldUpdateLocalItem(_ item: TodoItem, with reminder: EKReminder) -> Bool {
        let reminderModified = reminder.lastModifiedDate ?? .distantPast
        return reminderModified > item.lastModified
    }
    
    // MARK: - Helpers
    
    /// El calendario de recordatorios por defecto del usuario.
    private func defaultCalendar() -> EKCalendar {
        eventStore.defaultCalendarForNewReminders() ?? {
            // Crear calendario si no existe
            let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
            calendar.title = "Recordatorios"
            calendar.source = eventStore.sources.first { $0.sourceType == .local } ?? eventStore.sources.first!
            try? eventStore.saveCalendar(calendar, commit: true)
            return calendar
        }()
    }
    
    /// Maneja cambios externos en la app Recordatorios.
    @objc private func handleExternalChange() {
        guard isSyncEnabled else { return }
        
        Task {
            // Esperar un poco para agrupar cambios rapidos
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 segundo
            await performFullSync()
        }
    }
    
    // MARK: - Public Sync Triggers
    
    /// Sincroniza una tarea individual con Recordatorios.
    func syncItem(_ item: TodoItem) async {
        guard isSyncEnabled else { return }
        guard await ensureAuthorized() else { return }
        
        do {
            if let reminderID = item.reminderIdentifier {
                // Actualizar recordatorio existente
                if let reminder = eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder {
                    try updateReminder(reminder, from: item)
                } else {
                    // El recordatorio fue borrado en la app Recordatorios, crear uno nuevo
                    let newReminderID = try await createReminder(from: item)
                    updateLocalItem(item, withReminderID: newReminderID)
                }
            } else {
                // Crear nuevo recordatorio
                let reminderID = try await createReminder(from: item)
                updateLocalItem(item, withReminderID: reminderID)
            }
        } catch {
            lastSyncError = "Error al sincronizar tarea: \(error.localizedDescription)"
        }
    }
    
    /// Elimina una tarea de Recordatorios cuando se borra localmente.
    func deleteItem(_ item: TodoItem) async {
        guard isSyncEnabled else { return }
        guard await ensureAuthorized() else { return }
        
        if let reminderID = item.reminderIdentifier {
            do {
                try deleteReminder(withID: reminderID)
            } catch {
                lastSyncError = "Error al eliminar recordatorio: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Errors

enum SyncError: LocalizedError {
    case unauthorized
    case reminderNotFound
    
    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "No hay permisos para acceder a Recordatorios"
        case .reminderNotFound:
            return "Recordatorio no encontrado"
        }
    }
}
