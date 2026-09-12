import Combine
import Foundation

@MainActor
final class TaskStore: ObservableObject {
    @Published var items: [TodoItem] = [] {
        didSet {
            save()
            ReminderScheduler.shared.sync(items)
        }
    }

    /// Lo ultimo que se quito de la lista, para poder deshacerlo.
    @Published private var lastRemoval: [Removal] = []

    private let key = "todo.items"

    init() {
        load()
        // Al arrancar puede haber notificaciones huerfanas de una sesion
        // anterior, o fechas que ya pasaron con el Mac apagado.
        ReminderScheduler.shared.sync(items)
    }

    var pendingCount: Int { items.filter { !$0.isDone }.count }

    var canUndo: Bool { !lastRemoval.isEmpty }

    func add(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        items.append(TodoItem(title: t))
    }

    func remove(_ item: TodoItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        lastRemoval = [Removal(item: items[index], index: index)]
        items.remove(at: index)
    }

    func clearDone() {
        let removed = items.enumerated()
            .filter { $0.element.isDone }
            .map { Removal(item: $0.element, index: $0.offset) }
        guard !removed.isEmpty else { return }
        lastRemoval = removed
        items.removeAll { $0.isDone }
    }

    /// Reinserta lo ultimo que se quito, en su posicion original. Vale tanto
    /// para una tarea borrada con la x como para el lote de "Limpiar hechas".
    func undoRemoval() {
        guard !lastRemoval.isEmpty else { return }
        // De indice menor a mayor: asi cada insercion deja hueco para la
        // siguiente y el orden original se reconstruye.
        for removal in lastRemoval.sorted(by: { $0.index < $1.index }) {
            items.insert(removal.item, at: min(removal.index, items.count))
        }
        lastRemoval = []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([TodoItem].self, from: data)
        else { return }
        items = decoded
    }
}

private extension TaskStore {
    struct Removal {
        let item: TodoItem
        let index: Int
    }
}
