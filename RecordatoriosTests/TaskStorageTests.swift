import XCTest
@testable import Recordatorios

final class TaskStorageTests: XCTestCase {
    private var directory: URL!
    private var storage: TaskStorage!
    private var suiteName: String!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TaskStorageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storage = TaskStorage(fileURL: directory.appendingPathComponent("tasks.json"))
        suiteName = "TaskStorageTests-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    // MARK: - Lectura y escritura

    func testLoadWithoutFileReturnsEmpty() throws {
        XCTAssertEqual(try storage.load(), [])
    }

    /// Las fechas se guardan al milisegundo, asi que el item de ida tiene que
    /// nacer ya redondeado para que la comparacion diga algo del formato y no
    /// de los microsegundos que trae Date().
    func testSaveThenLoadRoundTripsEveryField() throws {
        var conFecha = TodoItem(
            title: "Con fecha",
            isDone: false,
            dueDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        conFecha.reminderIdentifier = "ABC-123"
        conFecha.lastModified = Date(timeIntervalSince1970: 1_700_000_000.500)

        var hecha = TodoItem(title: "Hecha", isDone: true)
        hecha.lastModified = Date(timeIntervalSince1970: 1_700_000_001.250)

        let items = [conFecha, hecha]
        try storage.save(items)

        XCTAssertEqual(try storage.load(), items)
    }

    /// Los microsegundos de un Date recien creado no sobreviven: el formato
    /// llega al milisegundo. Documentado aqui para que no sorprenda.
    func testSaveRoundsDatesToTheMillisecond() throws {
        var item = TodoItem(title: "Ahora")
        item.lastModified = Date(timeIntervalSince1970: 1_700_000_000.123_456)

        try storage.save([item])

        let recovered = try XCTUnwrap(try storage.load().first).lastModified
        XCTAssertEqual(
            recovered.timeIntervalSince1970,
            1_700_000_000.123,
            accuracy: 0.0005
        )
    }

    /// Las fechas pasan por texto ISO: si se truncaran los milisegundos, el
    /// item de vuelta no seria igual al de ida.
    func testSavePreservesSubSecondPrecision() throws {
        let precise = Date(timeIntervalSince1970: 1_800_000_000.123)
        var item = TodoItem(title: "Precisa")
        item.lastModified = precise

        try storage.save([item])

        XCTAssertEqual(try storage.load().first?.lastModified, precise)
    }

    func testSaveReplacesPreviousContents() throws {
        try storage.save([TodoItem(title: "Primera")])
        try storage.save([TodoItem(title: "Segunda")])

        XCTAssertEqual(try storage.load().map(\.title), ["Segunda"])
    }

    func testSaveCreatesMissingIntermediateDirectories() throws {
        let nested = directory
            .appendingPathComponent("a/b/c", isDirectory: true)
            .appendingPathComponent("tasks.json")
        let deepStorage = TaskStorage(fileURL: nested)

        try deepStorage.save([TodoItem(title: "Honda")])

        XCTAssertEqual(try deepStorage.load().map(\.title), ["Honda"])
    }

    /// Un fichero de una version futura se rechaza entero: cargarlo a medias
    /// y volver a guardarlo borraria los campos que esta version no conoce.
    func testLoadRejectsFileFromNewerVersion() throws {
        let future = TaskFile.currentVersion + 1
        let json = #"{"version": \#(future), "items": []}"#
        try Data(json.utf8).write(to: storage.fileURL)

        XCTAssertThrowsError(try storage.load()) { error in
            XCTAssertEqual(
                error as? StorageError,
                .futureVersion(found: future, supported: TaskFile.currentVersion)
            )
        }
    }

    func testSavedFileCarriesCurrentVersion() throws {
        try storage.save([TodoItem(title: "Cualquiera")])

        let raw = try JSONSerialization.jsonObject(
            with: Data(contentsOf: storage.fileURL)
        ) as? [String: Any]

        XCTAssertEqual(raw?["version"] as? Int, TaskFile.currentVersion)
    }

    // MARK: - Migracion desde UserDefaults

    func testMigrationMovesLegacyBlobIntoFileAndDropsTheKey() throws {
        let defaults = UserDefaults(suiteName: suiteName)!
        let legacy = [TodoItem(title: "De UserDefaults", isDone: true)]
        // El blob viejo se escribia con un JSONEncoder sin configurar.
        defaults.set(try JSONEncoder().encode(legacy), forKey: "todo.items")

        let migrated = try storage.migrateLegacyDefaults(from: defaults, key: "todo.items")

        XCTAssertTrue(migrated)
        XCTAssertEqual(try storage.load().map(\.title), ["De UserDefaults"])
        XCTAssertNil(defaults.data(forKey: "todo.items"), "la clave vieja deberia quedar borrada")
    }

    func testMigrationDoesNothingWhenFileAlreadyExists() throws {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(try JSONEncoder().encode([TodoItem(title: "Vieja")]), forKey: "todo.items")
        try storage.save([TodoItem(title: "La del fichero")])

        let migrated = try storage.migrateLegacyDefaults(from: defaults, key: "todo.items")

        XCTAssertFalse(migrated)
        XCTAssertEqual(try storage.load().map(\.title), ["La del fichero"], "manda el fichero")
        XCTAssertNotNil(defaults.data(forKey: "todo.items"), "y no se toca la clave vieja")
    }

    func testMigrationIsANoOpWithoutLegacyData() throws {
        let defaults = UserDefaults(suiteName: suiteName)!

        XCTAssertFalse(try storage.migrateLegacyDefaults(from: defaults, key: "todo.items"))
        XCTAssertEqual(try storage.load(), [])
    }
}
