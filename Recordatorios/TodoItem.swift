import Foundation

struct TodoItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var isDone: Bool = false
    /// Campo opcional a proposito: el JSON ya guardado en UserDefaults no lo
    /// trae y Codable lo decodifica como nil, asi que las tareas viejas
    /// sobreviven sin migracion.
    var dueDate: Date?

    var isOverdue: Bool {
        guard !isDone, let dueDate else { return false }
        return dueDate < .now
    }
}
