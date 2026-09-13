import EventKit
import Foundation
import SwiftUI
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
    
    /// Todas las listas de Recordatorios del usuario, para poder elegir y
    /// filtrar. Estan todas, tambien las que no se sincronizan.
    @Published private(set) var lists: [TaskList] = []

    /// Las listas que se sincronizan. nil mientras el usuario no elija, y
    /// entonces son todas: una app que al activarse no trae nada no se
    /// entiende.
    @Published private(set) var enabledListIDs: Set<String>?

    /// Errores de sincronizacion para mostrar en la UI.
    @Published var lastSyncError: String?
    
    /// Ultima vez que se sincronizo correctamente.
    @Published var lastSyncDate: Date?
    
    private let syncEnabledKey = "reminders.sync.enabled"
    private let lastSyncKey = "reminders.sync.lastDate"
    private let enabledListsKey = "reminders.sync.lists"

    /// performFullSync escribe en TaskStore.items, y el didSet de esa
    /// propiedad vuelve a llamar a performFullSync. Sin esta guarda cada
    /// sincronizacion desencadena otra.
    private var isSyncing = false
    
    private init() {
        self.authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        self.isSyncEnabled = UserDefaults.standard.bool(forKey: syncEnabledKey)
        
        if let timestamp = UserDefaults.standard.object(forKey: lastSyncKey) as? Date {
            self.lastSyncDate = timestamp
        }

        if let stored = UserDefaults.standard.array(forKey: enabledListsKey) as? [String] {
            self.enabledListIDs = Set(stored)
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
                                self.lastSyncError = "Permission request failed: \(error.localizedDescription)"
                            }
                            continuation.resume(returning: granted)
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.authorizationStatus = .denied
                self.lastSyncError = "Permission request failed: \(error.localizedDescription)"
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
        
        lastSyncError = "Permission denied. Enable it in System Settings."
        return false
    }
    
    // MARK: - Sync Operations
    
    /// Sincronizacion completa bidireccional.
    /// 1. Sube tareas locales que no esten en Recordatorios
    /// 2. Baja recordatorios que no esten en local
    /// 3. Actualiza los que existen en ambos lados
    func performFullSync() async {
        guard isSyncEnabled, !isSyncing else { return }
        guard await ensureAuthorized() else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            // 1. Fundir duplicados que ya hubiera en la lista local
            mergeDuplicateLocalItems()

            // 2. Obtener los recordatorios de todas las listas, no solo de la
            // de por defecto, que es lo que las colapsaba todas en una.
            refreshLists()
            let predicate = eventStore.predicateForReminders(in: enabledCalendars())
            let reminders = try await fetchReminders(matching: predicate)
            
            // 3. Crear mapas para comparacion rapida. uniquingKeysWith y no
            // uniqueKeysWithValues: con dos claves iguales lo segundo aborta
            // el proceso.
            let remindersByID = Dictionary(
                reminders.map { ($0.calendarItemIdentifier, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            
            // 4. Sincronizar en ambas direcciones
            try await syncLocalToReminders(remindersByID: remindersByID)

            // El mapa se calcula aqui y no antes: syncLocalToReminders puede
            // haber enlazado tareas locales con recordatorios ya existentes.
            let localItemsByReminderID = Dictionary(
                TaskStore.shared.items.compactMap { item -> (String, TodoItem)? in
                    guard let reminderID = item.reminderIdentifier else { return nil }
                    return (reminderID, item)
                },
                uniquingKeysWith: { first, _ in first }
            )
            try await syncRemindersToLocal(reminders, localItemsByReminderID: localItemsByReminderID)
            
            // 5. Actualizar estado
            DiagnosticLog.shared.log(
                .sync,
                "Synced \(TaskStore.shared.items.count) tasks against \(reminders.count) reminders in \(lists.count) lists"
            )
            lastSyncError = nil
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)
            
        } catch {
            lastSyncError = "Sync failed: \(error.localizedDescription)"
            DiagnosticLog.shared.log(.sync, "Failed: \(error.localizedDescription)")
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
    private func syncLocalToReminders(remindersByID: [String: EKReminder]) async throws {
        // Recordatorios que todavia no tiene ninguna tarea local, indexados
        // por lista y titulo: son los candidatos a adoptar en vez de duplicar.
        // Primero lo que los recordatorios saben y las tareas no, de una sola
        // vez. Item a item seria una escritura del fichero entero por tarea, y
        // en la primera sincronizacion tras actualizar cambian todas.
        adoptRemoteMetadata(from: remindersByID)
        let localItems = TaskStore.shared.items

        let claimedIDs = Set(localItems.compactMap(\.reminderIdentifier))
        var unclaimedByKey: [String: EKReminder] = [:]
        for reminder in remindersByID.values
        where !claimedIDs.contains(reminder.calendarItemIdentifier) {
            guard let key = dedupeKey(
                list: reminder.calendar?.calendarIdentifier,
                title: reminder.title ?? "",
                isCompleted: reminder.isCompleted
            ) else { continue }
            if unclaimedByKey[key] == nil { unclaimedByKey[key] = reminder }
        }

        for item in localItems {
            if let reminderID = item.reminderIdentifier,
               let existingReminder = remindersByID[reminderID] {
                // La lista se reconcilia siempre, no solo cuando hay cambios
                // que subir: si no, las tareas sincronizadas antes de que
                // existieran las listas se quedaban sin ella para siempre.
                // Actualizar recordatorio existente si la tarea local es mas
                // reciente. La lista y los campos que faltaban ya los adopto
                // la pasada de arriba.
                if shouldUpdateReminder(existingReminder, with: item) {
                    try updateReminder(existingReminder, from: item)
                }
            } else if let key = dedupeKey(
                        list: item.listIdentifier,
                        title: item.title,
                        isCompleted: item.isDone
                      ),
                      let twin = unclaimedByKey.removeValue(forKey: key) {
                // Ya hay un recordatorio con ese titulo: se adopta. Crear uno
                // nuevo es lo que dejaba la tarea por duplicado en los dos
                // lados.
                updateLocalItem(item, withReminderID: twin.calendarItemIdentifier)
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
            } else if TaskStore.shared.archived.contains(where: {
                $0.reminderIdentifier == reminderID
            }) {
                // Ya se archivo. El recordatorio sigue en la app Recordatorios
                // a proposito, asi que sin esta comprobacion la siguiente
                // pasada lo devolvia a la lista activa y archivar no servia de
                // nada.
                continue
            } else if let key = dedupeKey(
                        list: reminder.calendar?.calendarIdentifier,
                        title: reminder.title ?? "",
                        isCompleted: reminder.isCompleted
                      ),
                      TaskStore.shared.items.contains(where: {
                          dedupeKey(list: $0.listIdentifier, title: $0.title, isCompleted: $0.isDone) == key
                      }) {
                // Ya hay una tarea local con ese titulo: o se acaba de enlazar
                // arriba, o la app Recordatorios tiene el recordatorio por
                // duplicado. En ninguno de los dos casos toca crear otra.
                continue
            } else {
                // Crear nueva tarea local desde recordatorio
                createLocalItem(from: reminder)
            }
        }
    }

    /// Funde las tareas locales que comparten titulo en una sola. Gana la
    /// primera de la lista; de las demas se rescata el reminderIdentifier si
    /// ella no tiene, y el estado de la mas recientemente modificada.
    private func mergeDuplicateLocalItems() {
        var survivorIndexByTitle: [String: Int] = [:]
        var merged: [TodoItem] = []

        for item in TaskStore.shared.items {
            guard let key = dedupeKey(
                list: item.listIdentifier,
                title: item.title,
                isCompleted: item.isDone
            ) else {
                merged.append(item)
                continue
            }

            guard let index = survivorIndexByTitle[key] else {
                survivorIndexByTitle[key] = merged.count
                merged.append(item)
                continue
            }

            var survivor = merged[index]
            if item.lastModified > survivor.lastModified {
                survivor.isDone = item.isDone
                survivor.dueDate = item.dueDate
                survivor.lastModified = item.lastModified
            }
            // Lo que la superviviente no sepa, se lo lleva de la otra: fundir
            // dos tareas no puede costar una nota.
            survivor.notes = survivor.notes ?? item.notes
            survivor.priorityValue = survivor.priorityValue ?? item.priorityValue
            survivor.urlString = survivor.urlString ?? item.urlString
            survivor.recurrenceSummary = survivor.recurrenceSummary ?? item.recurrenceSummary
            survivor.reminderIdentifier = survivor.reminderIdentifier ?? item.reminderIdentifier
            survivor.listIdentifier = survivor.listIdentifier ?? item.listIdentifier
            survivor.listTitle = survivor.listTitle ?? item.listTitle
            merged[index] = survivor
        }

        guard merged.count != TaskStore.shared.items.count else { return }
        DiagnosticLog.shared.log(
            .sync,
            "Merged \(TaskStore.shared.items.count - merged.count) duplicates by title"
        )
        TaskStore.shared.items = merged
    }

    /// La clave con la que se decide si dos cosas son la misma tarea.
    ///
    /// Lleva la lista delante porque el mismo titulo en dos listas son dos
    /// tareas legitimas. Y devuelve nil para las completadas: comprar leche
    /// tres martes distintos son tres hechos con su fecha, no un duplicado.
    /// Deduplicarlos borraba el historial, que es justo lo que esta app
    /// existe para guardar.
    static func dedupeKey(listID: String, title: String, isCompleted: Bool) -> String? {
        guard !isCompleted else { return nil }
        return listID + "\u{1}" + normalizedTitle(title)
    }

    /// Una tarea sin lista se compara contra la de por defecto, que es donde
    /// acabara.
    private func dedupeKey(list: String?, title: String, isCompleted: Bool) -> String? {
        Self.dedupeKey(
            listID: list ?? defaultCalendar().calendarIdentifier,
            title: title,
            isCompleted: isCompleted
        )
    }

    /// Todas las listas de recordatorios del usuario.
    private func reminderCalendars() -> [EKCalendar] {
        let calendars = eventStore.calendars(for: .reminder)
        return calendars.isEmpty ? [defaultCalendar()] : calendars
    }

    /// Solo las que el usuario quiere sincronizar.
    private func enabledCalendars() -> [EKCalendar] {
        guard let enabledListIDs else { return reminderCalendars() }
        let elegidas = reminderCalendars().filter { enabledListIDs.contains($0.calendarIdentifier) }
        return elegidas.isEmpty ? [] : elegidas
    }

    func isEnabled(_ list: TaskList) -> Bool {
        enabledListIDs?.contains(list.id) ?? true
    }

    /// Activa o desactiva una lista.
    ///
    /// Al desactivarla se retiran de la lista local sus tareas ya
    /// sincronizadas: siguen en la app Recordatorios, asi que no se pierde
    /// nada, y volveran solas si se reactiva. Las que nunca llegaron a
    /// sincronizarse se quedan, porque esas si existen solo aqui.
    func setList(_ list: TaskList, enabled: Bool) {
        var seleccion = enabledListIDs ?? Set(lists.map(\.id))
        if enabled {
            seleccion.insert(list.id)
        } else {
            seleccion.remove(list.id)
        }
        enabledListIDs = seleccion
        UserDefaults.standard.set(Array(seleccion), forKey: enabledListsKey)

        if !enabled {
            let antes = TaskStore.shared.items.count
            TaskStore.shared.dropSyncedItems(inList: list.id)
            DiagnosticLog.shared.log(
                .sync,
                "Stopped syncing \(list.title), removed \(antes - TaskStore.shared.items.count) tasks"
            )
        }

        Task { await performFullSync() }
    }

    func refreshLists() {
        lists = reminderCalendars().map {
            TaskList(id: $0.calendarIdentifier, title: $0.title, color: Color(nsColor: $0.color))
        }
    }

    /// Titulos comparables: sin espacios de sobra, sin distinguir mayusculas
    /// ni acentos, para que "Kit corta-unas" y "Kit corta-uñas" no convivan.
    private static func normalizedTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
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
        reminder.calendar = calendar(withID: item.listIdentifier) ?? defaultCalendar()
        applyDetails(of: item, to: reminder)
        // completionDate manda: asignarla ya deja isCompleted en true, y
        // conserva el "cuando" en vez de solo el "si".
        reminder.completionDate = item.completedAt
        
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
        reminder.completionDate = item.completedAt
        applyDetails(of: item, to: reminder)
        
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
        var item = TodoItem(title: reminder.title ?? "Untitled")

        // Las fechas reales de Recordatorios, no aproximaciones: son lo que
        // alimenta el registro del dia.
        item.createdAt = reminder.creationDate ?? Date()
        item.completedAt = Self.completionDate(of: reminder)
        item.listIdentifier = reminder.calendar?.calendarIdentifier
        item.listTitle = reminder.calendar?.title

        if let dueDateComponents = reminder.dueDateComponents,
           let dueDate = Calendar.current.date(from: dueDateComponents) {
            item.dueDate = dueDate
        }
        
        item.reminderIdentifier = reminder.calendarItemIdentifier
        item.lastModified = reminder.lastModifiedDate ?? Date()
        Self.readDetails(of: reminder, into: &item)

        TaskStore.shared.items.append(item)
    }
    
    /// Actualiza una tarea local existente con datos de un recordatorio.
    private func updateLocalItem(from reminder: EKReminder) {
        guard let index = TaskStore.shared.items.firstIndex(where: {
            $0.reminderIdentifier == reminder.calendarItemIdentifier
        }) else { return }
        
        var item = TaskStore.shared.items[index]
        item.title = reminder.title ?? item.title
        item.completedAt = Self.completionDate(of: reminder)
        item.listIdentifier = reminder.calendar?.calendarIdentifier
        item.listTitle = reminder.calendar?.title
        
        if let dueDateComponents = reminder.dueDateComponents,
           let dueDate = Calendar.current.date(from: dueDateComponents) {
            item.dueDate = dueDate
        } else {
            item.dueDate = nil
        }
        
        item.lastModified = reminder.lastModifiedDate ?? Date()
        Self.readDetails(of: reminder, into: &item)

        TaskStore.shared.items[index] = item
    }
    
    /// Actualiza una tarea local con el ID del recordatorio tras crearlo o
    /// adoptarlo. Se lleva tambien la lista: al adoptar, la del recordatorio
    /// manda; al crear, es la que acaba de recibir.
    private func updateLocalItem(_ item: TodoItem, withReminderID reminderID: String) {
        guard let index = TaskStore.shared.items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        var updatedItem = TaskStore.shared.items[index]
        updatedItem.reminderIdentifier = reminderID
        if let reminder = eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder {
            updatedItem.listIdentifier = reminder.calendar?.calendarIdentifier
            updatedItem.listTitle = reminder.calendar?.title
        }
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
    
    // MARK: - Notas, prioridad, URL y repeticion

    /// Escribe en el recordatorio los campos que la tarea conoce.
    ///
    /// Un campo a nil no se toca. La tarea que lo tiene a nil no es que lo
    /// quiera vacio: es que nunca supo de el, porque se creo con una version
    /// de la app anterior a estos campos. Escribirlo borraria una nota que el
    /// usuario si escribio, y esta app existe para no perder ese registro.
    /// Para vaciarlos de verdad se guarda la cadena vacia, o el 0 en la
    /// prioridad.
    ///
    /// Las reglas de repeticion no se tocan nunca: esta app no las edita, y
    /// EventKit las quita si le escribes una lista vacia.
    private func applyDetails(of item: TodoItem, to reminder: EKReminder) {
        if let notes = item.notes {
            reminder.notes = notes.isEmpty ? nil : notes
        }

        if let priorityValue = item.priorityValue {
            reminder.priority = priorityValue
        }

        if let urlString = item.urlString {
            let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            reminder.url = trimmed.isEmpty ? nil : URL(string: trimmed)
        }
    }

    /// Copia a la tarea los campos del recordatorio. Lo que diga Recordatorios
    /// manda, porque a este punto solo se llega cuando el recordatorio es el
    /// mas reciente de los dos.
    static func readDetails(of reminder: EKReminder, into item: inout TodoItem) {
        item.notes = reminder.notes ?? ""
        item.priorityValue = reminder.priority
        item.urlString = reminder.url?.absoluteString ?? ""
        item.recurrenceSummary = recurrenceSummary(of: reminder)
    }

    /// Rellena solo los campos que la tarea no conoce, sin pisar los que si.
    ///
    /// Es lo que hace que una tarea creada antes de que existieran estos
    /// campos acabe enterandose de sus notas, aunque sea ella la mas reciente
    /// y por tanto la que manda en todo lo demas.
    static func adoptUnknownDetails(of reminder: EKReminder, into item: inout TodoItem) -> Bool {
        var changed = false

        if item.notes == nil {
            item.notes = reminder.notes ?? ""
            changed = true
        }
        if item.priorityValue == nil {
            item.priorityValue = reminder.priority
            changed = true
        }
        if item.urlString == nil {
            item.urlString = reminder.url?.absoluteString ?? ""
            changed = true
        }

        // La repeticion es siempre del recordatorio: aqui no se edita.
        let summary = recurrenceSummary(of: reminder)
        if item.recurrenceSummary != summary {
            item.recurrenceSummary = summary
            changed = true
        }

        return changed
    }

    /// Como se repite, en una linea. nil si no se repite.
    static func recurrenceSummary(of reminder: EKReminder) -> String? {
        guard let rule = reminder.recurrenceRules?.first else { return nil }
        return summary(of: rule)
    }

    static func summary(of rule: EKRecurrenceRule) -> String {
        let interval = max(rule.interval, 1)
        let unit: String
        switch rule.frequency {
        case .daily: unit = interval == 1 ? "day" : "days"
        case .weekly: unit = interval == 1 ? "week" : "weeks"
        case .monthly: unit = interval == 1 ? "month" : "months"
        case .yearly: unit = interval == 1 ? "year" : "years"
        @unknown default: unit = interval == 1 ? "time" : "times"
        }
        return interval == 1 ? "Every \(unit)" : "Every \(interval) \(unit)"
    }

    /// Recordatorios puede marcar una tarea como completada sin dejar fecha.
    /// En ese caso hay que inventar una o la tarea quedaria como pendiente.
    private static func completionDate(of reminder: EKReminder) -> Date? {
        guard reminder.isCompleted else { return nil }
        return reminder.completionDate ?? reminder.lastModifiedDate ?? Date()
    }

    /// El calendario de recordatorios por defecto del usuario.
    private func defaultCalendar() -> EKCalendar {
        eventStore.defaultCalendarForNewReminders() ?? {
            // Crear calendario si no existe
            let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
            calendar.title = "Tasks"
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
            lastSyncError = "Could not sync task: \(error.localizedDescription)"
        }
    }
    
    /// Cambia una tarea de lista, en local y en Recordatorios.
    func move(_ item: TodoItem, to list: TaskList) async {
        guard let index = TaskStore.shared.items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        var moved = TaskStore.shared.items[index]
        moved.listIdentifier = list.id
        moved.listTitle = list.title
        moved.lastModified = Date()
        TaskStore.shared.items[index] = moved

        guard isSyncEnabled,
              let reminderID = moved.reminderIdentifier,
              let reminder = eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder,
              let calendar = calendar(withID: list.id)
        else { return }

        reminder.calendar = calendar
        do {
            try eventStore.save(reminder, commit: true)
            DiagnosticLog.shared.log(.sync, "Moved \"\(moved.title)\" to \(list.title)")
        } catch {
            lastSyncError = "Could not move the task: \(error.localizedDescription)"
        }
    }

    /// Copia a cada tarea la lista en la que vive su recordatorio, y de paso
    /// los campos que ella todavia no conoce.
    ///
    /// El recordatorio manda en la lista: si se movio desde esta app, move()
    /// ya lo empujo antes, y si se movio desde la app Recordatorios, esto lo
    /// recoge. Escribe una sola vez al final: cada asignacion a
    /// TaskStore.items guarda el fichero entero y dispara otra pasada.
    private func adoptRemoteMetadata(from remindersByID: [String: EKReminder]) {
        var items = TaskStore.shared.items
        var changed = false

        for index in items.indices {
            guard let reminderID = items[index].reminderIdentifier,
                  let reminder = remindersByID[reminderID] else { continue }

            if Self.adoptUnknownDetails(of: reminder, into: &items[index]) {
                changed = true
            }

            let listID = reminder.calendar?.calendarIdentifier
            let listTitle = reminder.calendar?.title
            if items[index].listIdentifier != listID || items[index].listTitle != listTitle {
                items[index].listIdentifier = listID
                items[index].listTitle = listTitle
                changed = true
            }
        }

        guard changed else { return }
        TaskStore.shared.items = items
    }

    private func calendar(withID identifier: String?) -> EKCalendar? {
        guard let identifier else { return nil }
        return eventStore.calendars(for: .reminder)
            .first { $0.calendarIdentifier == identifier }
    }

    /// Elimina una tarea de Recordatorios cuando se borra localmente.
    func deleteItem(_ item: TodoItem) async {
        guard isSyncEnabled else { return }
        guard await ensureAuthorized() else { return }
        
        if let reminderID = item.reminderIdentifier {
            do {
                try deleteReminder(withID: reminderID)
            } catch {
                lastSyncError = "Could not delete reminder: \(error.localizedDescription)"
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
            return "No permission to access Reminders"
        case .reminderNotFound:
            return "Reminder not found"
        }
    }
}
