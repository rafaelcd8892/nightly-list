import XCTest
@testable import Recordatorios

/// systemSyncEnabled va en false en todos los stores de prueba: si no, montar
/// uno cancelaria las notificaciones reales del usuario y dispararia una
/// sincronizacion contra sus recordatorios de verdad.
@MainActor
final class TaskStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TaskStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore(file: String = "tasks.json") -> TaskStore {
        TaskStore(
            storage: TaskStorage(fileURL: directory.appendingPathComponent(file)),
            systemSyncEnabled: false
        )
    }

    // MARK: - Alta

    func testAddTrimsSurroundingWhitespace() {
        let store = makeStore()

        store.add("   Comprar pan\n")

        XCTAssertEqual(store.items.map(\.title), ["Comprar pan"])
    }

    func testAddIgnoresBlankTitles() {
        let store = makeStore()

        store.add("")
        store.add("   ")
        store.add("\n\t")

        XCTAssertTrue(store.items.isEmpty)
    }

    func testPendingCountIgnoresCompletedTasks() {
        let store = makeStore()
        store.add("Una")
        store.add("Otra")
        store.items[0].isDone = true

        XCTAssertEqual(store.pendingCount, 1)
    }

    // MARK: - Deshacer

    func testUndoRestoresARemovedTaskToItsOriginalPosition() {
        let store = makeStore()
        ["A", "B", "C"].forEach(store.add)
        let middle = store.items[1]

        store.remove(middle)
        XCTAssertEqual(store.items.map(\.title), ["A", "C"])

        store.undoRemoval()
        XCTAssertEqual(store.items.map(\.title), ["A", "B", "C"])
    }

    func testClearDoneRemovesOnlyCompletedTasks() {
        let store = makeStore()
        ["A", "B", "C"].forEach(store.add)
        store.items[0].isDone = true
        store.items[2].isDone = true

        store.clearDone()

        XCTAssertEqual(store.items.map(\.title), ["B"])
    }

    func testUndoRestoresAWholeClearDoneBatchInOrder() {
        let store = makeStore()
        ["A", "B", "C"].forEach(store.add)
        store.items[0].isDone = true
        store.items[2].isDone = true

        store.clearDone()
        store.undoRemoval()

        XCTAssertEqual(store.items.map(\.title), ["A", "B", "C"])
    }

    func testCanUndoOnlyAfterARemoval() {
        let store = makeStore()
        store.add("A")
        XCTAssertFalse(store.canUndo)

        store.remove(store.items[0])
        XCTAssertTrue(store.canUndo)

        store.undoRemoval()
        XCTAssertFalse(store.canUndo, "una vez deshecho no queda nada que deshacer")
    }

    func testUndoWithNothingRemovedDoesNotChangeTheList() {
        let store = makeStore()
        ["A", "B"].forEach(store.add)

        store.undoRemoval()

        XCTAssertEqual(store.items.map(\.title), ["A", "B"])
    }

    func testClearDoneWithNothingCompletedLeavesNothingToUndo() {
        let store = makeStore()
        ["A", "B"].forEach(store.add)

        store.clearDone()

        XCTAssertEqual(store.items.map(\.title), ["A", "B"])
        XCTAssertFalse(store.canUndo)
    }

    // MARK: - Persistencia

    func testTasksSurviveANewStoreOnTheSameFile() {
        let first = makeStore()
        first.add("Persistente")
        first.items[0].isDone = true

        let second = makeStore()

        XCTAssertEqual(second.items.map(\.title), ["Persistente"])
        XCTAssertEqual(second.items.first?.isDone, true)
    }

    func testRemovalIsPersistedToo() {
        let first = makeStore()
        ["A", "B"].forEach(first.add)
        first.remove(first.items[0])

        XCTAssertEqual(makeStore().items.map(\.title), ["B"])
    }

    // MARK: - Archivo

    /// "Limpiar hechas" ya no borra: lo hecho es el registro del dia.
    func testClearDoneArchivesInsteadOfDeleting() {
        let store = makeStore()
        ["A", "B"].forEach(store.add)
        store.items[0].isDone = true

        store.clearDone()

        XCTAssertEqual(store.items.map(\.title), ["B"])
        XCTAssertEqual(store.archived.map(\.title), ["A"])
        XCTAssertNotNil(store.archived.first?.archivedAt)
        XCTAssertNotNil(store.archived.first?.completedAt, "la fecha de completado se conserva")
    }

    func testUndoTakesTheTaskBackOutOfTheArchive() {
        let store = makeStore()
        ["A", "B"].forEach(store.add)
        store.items[0].isDone = true
        store.clearDone()

        store.undoRemoval()

        XCTAssertEqual(store.items.map(\.title), ["A", "B"])
        XCTAssertTrue(store.archived.isEmpty)
        XCTAssertNil(store.items.first?.archivedAt, "al volver deja de estar archivada")
    }

    /// La x es un borrado intencionado, no limpieza: esa si desaparece.
    func testDeletingWithTheCrossDoesNotArchive() {
        let store = makeStore()
        store.add("A")

        store.remove(store.items[0])

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.archived.isEmpty)
    }

    func testArchiveSurvivesANewStoreOnTheSameFile() {
        let first = makeStore()
        first.add("Archivame")
        first.items[0].isDone = true
        first.clearDone()

        let second = makeStore()

        XCTAssertTrue(second.items.isEmpty)
        XCTAssertEqual(second.archived.map(\.title), ["Archivame"])
    }

    // MARK: - completedAt

    func testMarkingDoneStampsACompletionDate() {
        let store = makeStore()
        store.add("A")
        XCTAssertNil(store.items[0].completedAt)

        store.items[0].isDone = true

        XCTAssertNotNil(store.items[0].completedAt)
    }

    func testUnmarkingClearsTheCompletionDate() {
        let store = makeStore()
        store.add("A")
        store.items[0].isDone = true

        store.items[0].isDone = false

        XCTAssertNil(store.items[0].completedAt)
        XCTAssertFalse(store.items[0].isDone)
    }

    /// Volver a marcar hecha algo que ya lo estaba no debe mover la fecha:
    /// si no, la sincronizacion con Recordatorios falsearia el registro.
    func testMarkingDoneTwiceKeepsTheOriginalDate() {
        let store = makeStore()
        store.add("A")
        store.items[0].isDone = true
        let first = store.items[0].completedAt

        store.items[0].isDone = true

        XCTAssertEqual(store.items[0].completedAt, first)
    }

    // MARK: - Anotar algo ya hecho (⌘Enter)

    func testAddCompletedStampsTheTaskAsDoneRightAway() {
        let store = makeStore()

        store.addCompleted("Ya lo hice")

        XCTAssertEqual(store.items.map(\.title), ["Ya lo hice"])
        XCTAssertTrue(store.items[0].isDone)
        XCTAssertNotNil(store.items[0].completedAt)
        XCTAssertEqual(store.pendingCount, 0, "no cuenta como pendiente")
    }

    func testAddCompletedTrimsAndIgnoresBlanks() {
        let store = makeStore()

        store.addCompleted("  Con espacios  ")
        store.addCompleted("   ")

        XCTAssertEqual(store.items.map(\.title), ["Con espacios"])
    }

    /// Lo anotado con ⌘Enter tiene que salir en el registro del dia.
    func testAddCompletedShowsUpInTodaysReport() {
        let store = makeStore()
        store.addCompleted("Del tirón")

        let report = DayReport(items: store.items, archived: store.archived)

        XCTAssertEqual(report.completed.map(\.title), ["Del tirón"])
    }

    // MARK: - Marcar desde la vista Hoy

    func testToggleCompletionMarksAnActiveTask() {
        let store = makeStore()
        store.add("A")

        store.toggleCompletion(id: store.items[0].id)

        XCTAssertTrue(store.items[0].isDone)
    }

    func testToggleCompletionUnmarksAnActiveTask() {
        let store = makeStore()
        store.addCompleted("A")

        store.toggleCompletion(id: store.items[0].id)

        XCTAssertFalse(store.items[0].isDone)
        XCTAssertNil(store.items[0].completedAt)
    }

    /// Desmarcar una archivada la devuelve a la lista: si no esta hecha, no
    /// tiene nada que hacer en el archivo.
    func testUnmarkingAnArchivedTaskBringsItBackToTheList() {
        let store = makeStore()
        store.addCompleted("Archivada")
        store.clearDone()
        let id = try! XCTUnwrap(store.archived.first).id

        store.toggleCompletion(id: id)

        XCTAssertEqual(store.items.map(\.title), ["Archivada"])
        XCTAssertTrue(store.archived.isEmpty)
        XCTAssertNil(store.items[0].archivedAt)
        XCTAssertFalse(store.items[0].isDone)
    }

    func testToggleCompletionIgnoresAnUnknownID() {
        let store = makeStore()
        store.add("A")

        store.toggleCompletion(id: UUID())

        XCTAssertFalse(store.items[0].isDone)
        XCTAssertEqual(store.items.count, 1)
    }

    /// Lo que hace la vista Hoy: coge el id de una fila del informe y lo
    /// manda al store. Si los ids no cuadraran, marcar no haria nada.
    func testTogglingByTheIDShownInTodaysReportUpdatesTheStore() {
        let store = makeStore()
        store.add("Pendiente de hoy")

        let before = DayReport(items: store.items, archived: store.archived)
        let id = try! XCTUnwrap(before.created.first).id

        store.toggleCompletion(id: id)

        let after = DayReport(items: store.items, archived: store.archived)
        XCTAssertEqual(after.completed.map(\.title), ["Pendiente de hoy"])
        XCTAssertTrue(after.created.isEmpty)
    }
}
