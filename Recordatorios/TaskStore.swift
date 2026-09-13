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

    /// Lo que salio de la lista con "Limpiar hechas". No se borra porque es
    /// el registro de lo que se hizo.
    @Published private(set) var archived: [TodoItem] = [] {
        didSet { save() }
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

    private static let isRunningTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// El storage se inyecta para poder montar el store contra un directorio
    /// temporal en los tests.
    init(storage: TaskStorage? = nil, systemSyncEnabled: Bool = true) {
        self.systemSyncEnabled = systemSyncEnabled
        if let storage {
            self.storage = storage
        } else if Self.isRunningTests {
            // Los tests corren hospedados en la app, asi que al arrancar el
            // host se crearia TaskStore.shared sobre el fichero real del
            // usuario. Cada pasada de tests le reescribiria sus tareas.
            self.storage = nil
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
        append(title, completedAt: nil)
    }

    /// Apunta algo que ya esta terminado, para el caso de "esto lo acabo de
    /// hacer y quiero que conste". Es la via del ⌘Enter en la captura rapida.
    func addCompleted(_ title: String) {
        append(title, completedAt: Date())
    }

    private func append(_ title: String, completedAt: Date?) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var item = TodoItem(title: trimmed)
        item.completedAt = completedAt
        items.append(item)
    }

    /// Marca o desmarca por id, este la tarea en la lista activa o ya en el
    /// archivo. Desmarcar una archivada la devuelve a la lista: si no esta
    /// hecha, no tiene nada que hacer en el archivo.
    func toggleCompletion(id: TodoItem.ID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].isDone.toggle()
            items[index].lastModified = Date()
            return
        }

        guard let index = archived.firstIndex(where: { $0.id == id }) else { return }
        var item = archived[index]
        item.isDone = false
        item.archivedAt = nil
        item.lastModified = Date()
        archived.remove(at: index)
        items.append(item)
    }

    func remove(_ item: TodoItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        // La x es un borrado intencionado, no limpieza: esa si desaparece.
        lastRemoval = [Removal(item: items[index], index: index, wasArchived: false)]
        
        // Eliminar de Recordatorios si esta sincronizado
        if systemSyncEnabled {
            let removedItem = items[index]
            Task {
                await RemindersSync.shared.deleteItem(removedItem)
            }
        }
        
        items.remove(at: index)
    }

    /// Retira las hechas de la lista activa y las manda al archivo.
    ///
    /// No borra: antes se llevaba por delante el registro del dia. Tampoco
    /// borra el recordatorio en la app Recordatorios, que guarda las
    /// completadas y es parte del mismo registro.
    func clearDone() {
        let stamp = Date()
        let removed = items.enumerated()
            .filter { $0.element.isDone }
            .map { offset, item -> Removal in
                var archivedItem = item
                archivedItem.archivedAt = stamp
                return Removal(item: archivedItem, index: offset, wasArchived: true)
            }
        guard !removed.isEmpty else { return }

        lastRemoval = removed
        archived.append(contentsOf: removed.map(\.item))
        items.removeAll { $0.isDone }

        DiagnosticLog.shared.log(.storage, "Archivadas \(removed.count) tareas hechas")
    }

    /// Reinserta lo ultimo que se quito, en su posicion original. Vale tanto
    /// para una tarea borrada con la x como para el lote de "Limpiar hechas".
    func undoRemoval() {
        guard !lastRemoval.isEmpty else { return }
        // De indice menor a mayor: asi cada insercion deja hueco para la
        // siguiente y el orden original se reconstruye.
        let returning = Set(lastRemoval.filter(\.wasArchived).map(\.item.id))
        if !returning.isEmpty {
            archived.removeAll { returning.contains($0.id) }
        }

        for removal in lastRemoval.sorted(by: { $0.index < $1.index }) {
            var item = removal.item
            item.archivedAt = nil
            items.insert(item, at: min(removal.index, items.count))
        }
        lastRemoval = []
    }

    private func save() {
        guard let storage else { return }
        do {
            try storage.save(items, archived: archived)
            storageError = nil
        } catch {
            storageError = "No se pudieron guardar las tareas: \(error.localizedDescription)"
            DiagnosticLog.shared.log(.storage, "Fallo al guardar: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let storage else {
            if !Self.isRunningTests {
                storageError = "No se pudo abrir la carpeta de datos de la app."
            }
            return
        }
        do {
            if try storage.migrateLegacyDefaults(from: .standard, key: Self.legacyDefaultsKey) {
                DiagnosticLog.shared.log(.storage, "Migradas las tareas de UserDefaults al fichero")
            }
            let loaded = try storage.load()
            // Asignar aunque venga vacio dispararia el didSet y reescribiria el
            // fichero en cada arranque; solo interesa cuando hay algo.
            if !loaded.items.isEmpty { items = loaded.items }
            if !loaded.archived.isEmpty { archived = loaded.archived }
            storageError = nil
            DiagnosticLog.shared.log(
                .storage,
                "Cargadas \(loaded.items.count) tareas y \(loaded.archived.count) archivadas"
            )
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
        /// true si fue al archivo; false si se borro de verdad. Deshacer tiene
        /// que sacarla del archivo en el primer caso.
        let wasArchived: Bool
    }
}
