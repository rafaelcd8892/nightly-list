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

    /// La lista a la que pertenece, que en EventKit es un EKCalendar. Nil
    /// significa la lista por defecto del usuario.
    var listIdentifier: String?

    /// El nombre de la lista, guardado aparte para poder pintarlo sin
    /// preguntarle a EventKit. La verdad es el identificador; esto se refresca
    /// en cada sincronizacion.
    var listTitle: String?

    /// Identificador del EKReminder correspondiente en la app Recordatorios.
    /// Nil si esta tarea no se ha sincronizado con Recordatorios.
    var reminderIdentifier: String?

    /// Las notas del recordatorio. Hasta ahora la sincronizacion las tiraba
    /// sin decir nada: se escribian en Recordatorios y desaparecian.
    ///
    /// nil no es lo mismo que vacio. nil significa "esta tarea no sabe nada de
    /// sus notas", y entonces la sincronizacion no las toca; la cadena vacia
    /// significa "el usuario las borro", y esa si se propaga. Sin esa
    /// distincion, la primera sincronizacion despues de actualizar borraria
    /// las notas de todos los recordatorios que ya existian.
    var notes: String?

    /// La prioridad cruda de EKReminder: 0 ninguna, 1-4 alta, 5 media, 6-9
    /// baja. Se guarda el entero y no el escalon para devolver el mismo numero
    /// que trajo el recordatorio. nil se lee igual que en notes: sin opinion.
    var priorityValue: Int?

    /// La URL del recordatorio, como texto. Se guarda en crudo para poder
    /// distinguir "sin opinion" (nil) de "el usuario la borro" (cadena vacia),
    /// que con un URL? no se puede.
    var urlString: String?

    /// Como se repite el recordatorio, en una linea y solo para leer. Esta app
    /// no edita repeticiones: las reglas de EventKit se quedan intactas y esto
    /// es la etiqueta que se pinta para que se vea que las hay.
    var recurrenceSummary: String?

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

    /// El escalon de prioridad, para la interfaz. Escribirlo deja el entero
    /// canonico del escalon.
    var priority: TaskPriority {
        get { TaskPriority(rawPriority: priorityValue ?? 0) }
        set { priorityValue = newValue.rawValue }
    }

    var hasNotes: Bool {
        !(notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var url: URL? {
        get {
            let text = (urlString ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return URL(string: text)
        }
        // Vacio en vez de nil: borrar la URL tiene que viajar a Recordatorios.
        set { urlString = newValue?.absoluteString ?? "" }
    }

    var isRecurring: Bool { recurrenceSummary != nil }
}

// MARK: - Lectura de ficheros anteriores

extension TodoItem {
    private enum CodingKeys: String, CodingKey {
        case id, title, createdAt, completedAt, archivedAt, dueDate
        case listIdentifier, listTitle
        case reminderIdentifier, lastModified
        case notes, priorityValue, urlString, recurrenceSummary
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
        listIdentifier = try container.decodeIfPresent(String.self, forKey: .listIdentifier)
        listTitle = try container.decodeIfPresent(String.self, forKey: .listTitle)
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        priorityValue = try container.decodeIfPresent(Int.self, forKey: .priorityValue)
        urlString = try container.decodeIfPresent(String.self, forKey: .urlString)
        recurrenceSummary = try container.decodeIfPresent(String.self, forKey: .recurrenceSummary)

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
        try container.encodeIfPresent(listIdentifier, forKey: .listIdentifier)
        try container.encodeIfPresent(listTitle, forKey: .listTitle)
        try container.encodeIfPresent(reminderIdentifier, forKey: .reminderIdentifier)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(priorityValue, forKey: .priorityValue)
        try container.encodeIfPresent(urlString, forKey: .urlString)
        try container.encodeIfPresent(recurrenceSummary, forKey: .recurrenceSummary)
        try container.encode(lastModified, forKey: .lastModified)
    }
}
