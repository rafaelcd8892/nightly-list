import Foundation

/// El tramo de tiempo en el que cae una tarea segun su fecha.
///
/// El orden del enum es el orden en que se ensenan: lo vencido primero, porque
/// es lo que reclama atencion, y lo que no tiene fecha al final.
enum DueBucket: Int, CaseIterable, Identifiable, Comparable {
    case overdue
    case today
    case tomorrow
    case thisWeek
    case later
    case noDate

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .overdue: return "Overdue"
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .thisWeek: return "This week"
        case .later: return "Later"
        case .noDate: return "No date"
        }
    }

    static func < (lhs: DueBucket, rhs: DueBucket) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// En que tramo cae una tarea.
    ///
    /// "Esta semana" son los seis dias siguientes a mañana, contados por dias
    /// de calendario y no por horas: una tarea para pasado mañana a las nueve
    /// de la noche esta en esta semana igual que una para las nueve de la
    /// mañana.
    static func of(
        _ item: TodoItem,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DueBucket {
        guard let dueDate = item.dueDate else { return .noDate }

        if dueDate < calendar.startOfDay(for: now) { return .overdue }
        if calendar.isDate(dueDate, inSameDayAs: now) { return .today }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        if calendar.isDate(dueDate, inSameDayAs: tomorrow) { return .tomorrow }

        guard let limit = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now))
        else { return .later }

        return dueDate < limit ? .thisWeek : .later
    }
}
