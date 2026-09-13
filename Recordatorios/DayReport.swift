import Foundation

/// La actividad de un dia: lo que se dio por hecho y lo que se apunto.
///
/// Mira la lista activa y el archivo a la vez, porque "Limpiar hechas" mueve
/// tareas al archivo y aun asi siguen siendo actividad del dia.
struct DayReport {
    let day: Date
    /// Completadas ese dia, de mas reciente a mas antigua.
    let completed: [TodoItem]
    /// Creadas ese dia y todavia sin completar. Las creadas y completadas el
    /// mismo dia salen solo en completed, para no contarlas dos veces.
    let created: [TodoItem]

    private let calendar: Calendar

    init(
        day: Date = Date(),
        items: [TodoItem],
        archived: [TodoItem] = [],
        calendar: Calendar = .current
    ) {
        self.day = day
        self.calendar = calendar

        let everything = items + archived

        completed = everything
            .filter { item in
                guard let completedAt = item.completedAt else { return false }
                return calendar.isDate(completedAt, inSameDayAs: day)
            }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        let completedIDs = Set(completed.map(\.id))
        created = everything
            .filter { item in
                !completedIDs.contains(item.id)
                    && calendar.isDate(item.createdAt, inSameDayAs: day)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var isEmpty: Bool { completed.isEmpty && created.isEmpty }

    /// El dia en Markdown, con el prompt de resumen pegado al final para
    /// poder pasarselo a un modelo sin tener que escribirlo cada vez.
    func markdown(prompt: String = SummaryPrompt.current) -> String {
        var lines = ["# \(Self.dayFormatter.string(from: day))", ""]

        if completed.isEmpty {
            lines += ["## Done", "", "_Nothing completed._", ""]
        } else {
            lines += ["## Done (\(completed.count))", ""]
            lines += Self.body(for: completed, showTime: true)
        }

        if !created.isEmpty {
            lines += ["## Still open (\(created.count))", ""]
            lines += Self.body(for: created, showTime: false)
        }

        lines += ["---", "", prompt]
        return lines.joined(separator: "\n")
    }

    /// Agrupa por referencia de ticket. Las que no llevan ninguna van al
    /// final, juntas.
    static func grouped(_ items: [TodoItem]) -> [(reference: String?, items: [TodoItem])] {
        var byReference: [String: [TodoItem]] = [:]
        var withoutReference: [TodoItem] = []

        for item in items {
            if let reference = item.ticketReference {
                byReference[reference, default: []].append(item)
            } else {
                withoutReference.append(item)
            }
        }

        var groups = byReference.keys.sorted().map {
            (reference: Optional($0), items: byReference[$0] ?? [])
        }
        if !withoutReference.isEmpty {
            groups.append((reference: nil, items: withoutReference))
        }
        return groups
    }

    /// Agrupa solo si hay alguna referencia. Si no hay ninguna, un encabezado
    /// de grupo no aportaria nada.
    ///
    /// En el export el orden es cronologico ascendente, al contrario que en la
    /// vista: ahi interesa lo ultimo que se cerro, y aqui se esta contando el
    /// dia de principio a fin.
    private static func body(for items: [TodoItem], showTime: Bool) -> [String] {
        let groups = grouped(items.sorted(by: chronologically))
        let hasReferences = groups.contains { $0.reference != nil }

        guard hasReferences else {
            return items.sorted(by: chronologically)
                .map { line(for: $0, showTime: showTime) } + [""]
        }

        var lines: [String] = []
        for group in groups {
            lines += ["### \(group.reference ?? "No ticket") (\(group.items.count))", ""]
            lines += group.items.map { line(for: $0, showTime: showTime) }
            lines.append("")
        }
        return lines
    }

    private static func chronologically(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        (lhs.completedAt ?? lhs.createdAt) < (rhs.completedAt ?? rhs.createdAt)
    }

    private static func line(for item: TodoItem, showTime: Bool) -> String {
        let box = item.isDone ? "[x]" : "[ ]"
        let time = showTime
            ? item.completedAt.map { " — \(timeFormatter.string(from: $0))" } ?? ""
            : ""
        return "- \(box) \(item.title)\(time)"
    }

    /// Locale fijo en ingles: el export es siempre en ingles, asi que no
    /// tiene que salir mezclado segun el idioma del Mac. Era justo lo que
    /// pasaba antes, con la cabecera en ingles y las secciones en espanol.
    private static let exportLocale = Locale(identifier: "en_US")

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = exportLocale
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = exportLocale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
