import Foundation

/// Lo que se guarda en disco. El numero de version esta desde el primer dia
/// para poder migrar mas adelante sin tener que adivinar el formato.
struct TaskFile: Codable, Equatable {
    /// 2: isDone paso a completedAt, y las tareas archivadas viven aparte.
    /// 3: cada tarea recuerda a que lista pertenece.
    static let currentVersion = 3

    var version: Int
    var items: [TodoItem]
    /// Lo que salio de la lista activa con "Limpiar hechas". Se guarda en vez
    /// de borrarse porque es el registro de lo que se hizo.
    var archived: [TodoItem]

    init(items: [TodoItem], archived: [TodoItem] = [], version: Int = TaskFile.currentVersion) {
        self.version = version
        self.items = items
        self.archived = archived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        items = try container.decode([TodoItem].self, forKey: .items)
        // Los ficheros de la version 1 no traen archivo.
        archived = try container.decodeIfPresent([TodoItem].self, forKey: .archived) ?? []
    }
}

enum StorageError: LocalizedError, Equatable {
    /// El fichero lo escribio una version mas nueva de la app.
    case futureVersion(found: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case let .futureVersion(found, supported):
            return "This task file is version \(found) and this app understands up to \(supported). "
                + "Update the app so you do not lose data."
        }
    }
}

/// Guarda las tareas en un JSON dentro de Application Support.
///
/// Vive fuera de TaskStore para poder probarla contra un directorio temporal,
/// sin tocar los datos reales del usuario.
struct TaskStorage {
    let fileURL: URL

    /// ~/Library/Containers/<app>/Data/Library/Application Support/Recordatorios/tasks.json
    static func defaultFileURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base
            .appendingPathComponent("NightlyList", isDirectory: true)
            .appendingPathComponent("tasks.json", isDirectory: false)
    }

    /// Un fichero que aun no existe no es un error: es una instalacion nueva.
    func load() throws -> TaskFile {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return TaskFile(items: [])
        }

        let file = try Self.decoder.decode(TaskFile.self, from: Data(contentsOf: fileURL))
        guard file.version <= TaskFile.currentVersion else {
            // Mejor negarse a abrirlo que cargarlo a medias y sobrescribir
            // campos que esta version no conoce.
            throw StorageError.futureVersion(
                found: file.version,
                supported: TaskFile.currentVersion
            )
        }
        return file
    }

    func save(_ items: [TodoItem], archived: [TodoItem] = []) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(TaskFile(items: items, archived: archived))
        // Atomico: un corte a media escritura deja el fichero anterior intacto
        // en vez de uno truncado.
        try data.write(to: fileURL, options: .atomic)
    }

    /// Pasa al fichero el blob que las versiones viejas guardaban en
    /// UserDefaults, y solo entonces borra la clave antigua. Devuelve true si
    /// hubo algo que migrar.
    ///
    /// No hace nada si el fichero ya existe: manda el fichero.
    @discardableResult
    func migrateLegacyDefaults(from defaults: UserDefaults, key: String) throws -> Bool {
        guard !FileManager.default.fileExists(atPath: fileURL.path),
              let data = defaults.data(forKey: key) else { return false }

        // El blob viejo se escribio con un JSONEncoder sin configurar.
        let items = try JSONDecoder().decode([TodoItem].self, from: data)
        try save(items)

        // Solo despues de que el fichero este en disco: si no, un fallo al
        // escribir se llevaria por delante la unica copia.
        defaults.removeObject(forKey: key)
        return true
    }

    /// ISO 8601 con milisegundos. El .iso8601 de serie trunca los
    /// sub-segundos, y lastModified es justo lo que decide quien gana al
    /// resolver conflictos con la app Recordatorios.
    ///
    /// La precision que sobrevive al viaje es el milisegundo: un Date recien
    /// creado trae microsegundos y los pierde. Sobra de largo, porque el
    /// lastModifiedDate de EventKit va al segundo.
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Los primeros ficheros se escribieron con el .iso8601 de serie, sin
    /// milisegundos, y el formateador de arriba no sabe leerlos.
    private static let legacyDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func parseDate(_ text: String) -> Date? {
        dateFormatter.date(from: text) ?? legacyDateFormatter.date(from: text)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(dateFormatter.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseDate(text) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Unreadable date: \(text)")
                )
            }
            return date
        }
        return decoder
    }
}
