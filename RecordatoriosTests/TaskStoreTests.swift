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
}
