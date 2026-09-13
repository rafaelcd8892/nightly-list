import Combine
import Foundation

@MainActor
final class TaskStore: ObservableObject {
    /// El popover y la ventana de captura rapida tienen que ver la misma
    /// lista, y el panel se abre desde el handler del atajo, fuera de
    /// cualquier jerarquia de vistas.
    static let shared = TaskStore()

    @Published var items: [TodoItem] = [] {
        didSet {
            save()
            guard systemSyncEnabled else { return }

            ReminderScheduler.shared.sync(items)

            // Sincronizar con la app Recordatorios si esta activado
            Task {
                await RemindersSync.shared.performFullSync()
            }
        }
    }

    /// Lo ultimo que se quito de la lista, para poder deshacerlo.
    @Published private var lastRemoval: [Removal] = []

    /// Ultimo fallo al leer o escribir el fichero, para avisar en el popover.
    /// Antes un error de disco se tragaba en silencio.
    @Published private(set) var storageError: String?

    private let storage: TaskStorage?

    /// Con esto en false el store no programa notificaciones ni habla con la
    /// app Recordatorios. Los tests lo necesitan: si no, montar un store de
    /// prueba cancelaria los avisos reales del usuario y dispararia una
    /// sincronizacion contra sus recordatorios de verdad.
    private let systemSyncEnabled: Bool

    private static let legacyDefaultsKey = "todo.items"

    /// El storage se inyecta para poder montar el store contra un directorio
    /// temporal en los tests.
    init(storage: TaskStorage? = nil, systemSyncEnabled: Bool = true) {
        self.systemSyncEnabled = systemSyncEnabled
        if let storage {
            self.storage = storage
        } else if let url = try? TaskStorage.defaultFileURL() {
            self.storage = TaskStorage(fileURL: url)
        } else {
            self.storage = nil
        }
        load()
        // Al arrancar puede haber notificaciones huerfanas de una sesion
        // anterior, o fechas que ya pasaron con el Mac apagado.
        if systemSyncEnabled {
            ReminderScheduler.shared.sync(items)
        }
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
        
        // Eliminar de Recordatorios si esta sincronizado
        if systemSyncEnabled {
            let removedItem = items[index]
            Task {
                await RemindersSync.shared.deleteItem(removedItem)
            }
        }
        
        items.remove(at: index)
    }

    func clearDone() {
        let removed = items.enumerated()
            .filter { $0.element.isDone }
            .map { Removal(item: $0.element, index: $0.offset) }
        guard !removed.isEmpty else { return }
        lastRemoval = removed
        
        // Eliminar de Recordatorios los que estan sincronizados
        if systemSyncEnabled {
            let removedItems = removed.map { $0.item }
            Task {
                for item in removedItems {
                    await RemindersSync.shared.deleteItem(item)
                }
            }
        }
        
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
        guard let storage else { return }
        do {
            try storage.save(items)
            storageError = nil
        } catch {
            storageError = "No se pudieron guardar las tareas: \(error.localizedDescription)"
            DiagnosticLog.shared.log(.storage, "Fallo al guardar: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let storage else {
            storageError = "No se pudo abrir la carpeta de datos de la app."
            return
        }
        do {
            if try storage.migrateLegacyDefaults(from: .standard, key: Self.legacyDefaultsKey) {
                DiagnosticLog.shared.log(.storage, "Migradas las tareas de UserDefaults al fichero")
            }
            let loaded = try storage.load()
            // Asignar aunque venga vacio dispararia el didSet y reescribiria el
            // fichero en cada arranque; solo interesa cuando hay algo.
            if !loaded.isEmpty { items = loaded }
            storageError = nil
            DiagnosticLog.shared.log(.storage, "Cargadas \(loaded.count) tareas")
        } catch {
            storageError = "No se pudieron leer las tareas: \(error.localizedDescription)"
            DiagnosticLog.shared.log(.storage, "Fallo al leer: \(error.localizedDescription)")
        }
    }
}

private extension TaskStore {
    struct Removal {
        let item: TodoItem
        let index: Int
    }
}
