import Foundation

struct TodoItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String

    /// Cuando se creo. Hace falta para la vista "Hoy": lo creado hoy cuenta
    /// como actividad del dia aunque no se haya terminado.
    var createdAt: Date = Date()

    /// Cuando se dio por hecha, no si esta hecha. Es la pieza central del
    /// registro del dia, y viaja por EventKit en EKReminder.completionDate.
    var completedAt: Date?

    /// Cuando se retiro de la lista activa al archivo. Las archivadas siguen
    /// contando para el historial: por eso se archivan y no se borran.
    var archivedAt: Date?

    var dueDate: Date?

    /// Identificador del EKReminder correspondiente en la app Recordatorios.
    /// Nil si esta tarea no se ha sincronizado con Recordatorios.
    var reminderIdentifier: String?

    /// Timestamp de la ultima modificacion. Se usa para resolver conflictos
    /// en la sincronizacion bidireccional.
    var lastModified: Date = Date()

    /// Fachada sobre completedAt para no reescribir la UI ni la
    /// sincronizacion: item.isDone.toggle() sigue funcionando. Al marcarla
    /// hecha se respeta la fecha que ya tuviera, para no falsear el registro
    /// cuando el dato viene de la app Recordatorios.
    var isDone: Bool {
        get { completedAt != nil }
        set { completedAt = newValue ? (completedAt ?? Date()) : nil }
    }

    var isOverdue: Bool {
        guard !isDone, let dueDate else { return false }
        return dueDate < .now
    }

    var isSyncedWithReminders: Bool {
        reminderIdentifier != nil
    }
}

// MARK: - Lectura de ficheros anteriores

extension TodoItem {
    private enum CodingKeys: String, CodingKey {
        case id, title, createdAt, completedAt, archivedAt, dueDate
        case reminderIdentifier, lastModified
        /// Solo se lee, nunca se escribe: es el campo de la version 1.
        case isDone
    }

    /// Los ficheros de la version 1 guardaban isDone como booleano y no
    /// tenian createdAt. Al convertirlos no hay forma de saber cuando se
    /// completo o se creo cada tarea, asi que se usa lastModified como la
    /// mejor aproximacion disponible. Queda dicho para que nadie lea esas
    /// fechas como exactas.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        reminderIdentifier = try container.decodeIfPresent(String.self, forKey: .reminderIdentifier)
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)

        let modified = try container.decodeIfPresent(Date.self, forKey: .lastModified) ?? Date()
        lastModified = modified
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? modified

        if let completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt) {
            self.completedAt = completedAt
        } else if try container.decodeIfPresent(Bool.self, forKey: .isDone) == true {
            self.completedAt = modified
        } else {
            self.completedAt = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(archivedAt, forKey: .archivedAt)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encodeIfPresent(reminderIdentifier, forKey: .reminderIdentifier)
        try container.encode(lastModified, forKey: .lastModified)
    }
}
