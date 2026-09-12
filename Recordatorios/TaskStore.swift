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

    private let key = "todo.items"

    init() {
        load()
        // Al arrancar puede haber notificaciones huerfanas de una sesion
        // anterior, o fechas que ya pasaron con el Mac apagado.
        ReminderScheduler.shared.sync(items)
    }

    var pendingCount: Int { items.filter { !$0.isDone }.count }

    func add(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        items.append(TodoItem(title: t))
    }

    func remove(_ item: TodoItem) { items.removeAll { $0.id == item.id } }

    func clearDone() { items.removeAll { $0.isDone } }

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
