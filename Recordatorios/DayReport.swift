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
    func markdown() -> String {
        var lines = ["# Recordatorios — \(Self.dayFormatter.string(from: day))", ""]

        if completed.isEmpty {
            lines += ["## Hecho", "", "_Nada completado._", ""]
        } else {
            lines += ["## Hecho (\(completed.count))", ""]
            lines += completed.map { item in
                let hour = item.completedAt.map { " — \(Self.timeFormatter.string(from: $0))" } ?? ""
                return "- [x] \(item.title)\(hour)"
            }
            lines.append("")
        }

        if !created.isEmpty {
            lines += ["## Apuntado y sin cerrar (\(created.count))", ""]
            lines += created.map { "- [ ] \($0.title)" }
            lines.append("")
        }

        lines += ["---", "", Self.summaryPrompt]
        return lines.joined(separator: "\n")
    }

    /// Va en el propio export para que copiar y pegar baste.
    static let summaryPrompt = """
        Resume mi jornada a partir de la lista de arriba, en español y en \
        tercera persona del plural o impersonal. Tres o cuatro frases, sin \
        vinetas. Agrupa por tema en vez de repetir la lista, di que quedo a \
        medias, y no inventes nada que no este ahi. Si la lista esta vacia, \
        dilo y no rellenes.
        """

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
