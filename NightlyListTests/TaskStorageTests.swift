import XCTest
@testable import NightlyList

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
        XCTAssertEqual(try storage.load().items, [])
    }

    /// Las fechas se guardan al milisegundo, asi que el item de ida tiene que
    /// nacer ya redondeado para que la comparacion diga algo del formato y no
    /// de los microsegundos que trae Date().
    func testSaveThenLoadRoundTripsEveryField() throws {
        var conFecha = TodoItem(
            title: "Con fecha",
            dueDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        conFecha.reminderIdentifier = "ABC-123"
        conFecha.createdAt = Date(timeIntervalSince1970: 1_699_000_000.250)
        conFecha.lastModified = Date(timeIntervalSince1970: 1_700_000_000.500)

        var hecha = TodoItem(title: "Hecha")
        hecha.createdAt = Date(timeIntervalSince1970: 1_699_000_001.500)
        hecha.completedAt = Date(timeIntervalSince1970: 1_700_000_000.750)
        hecha.lastModified = Date(timeIntervalSince1970: 1_700_000_001.250)

        let items = [conFecha, hecha]
        try storage.save(items)

        XCTAssertEqual(try storage.load().items, items)
    }

    /// Los microsegundos de un Date recien creado no sobreviven: el formato
    /// llega al milisegundo. Documentado aqui para que no sorprenda.
    func testSaveRoundsDatesToTheMillisecond() throws {
        var item = TodoItem(title: "Ahora")
        item.lastModified = Date(timeIntervalSince1970: 1_700_000_000.123_456)

        try storage.save([item])

        let recovered = try XCTUnwrap(try storage.load().items.first).lastModified
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
        item.createdAt = precise
        item.lastModified = precise

        try storage.save([item])

        XCTAssertEqual(try storage.load().items.first?.lastModified, precise)
    }

    func testSaveReplacesPreviousContents() throws {
        try storage.save([TodoItem(title: "Primera")])
        try storage.save([TodoItem(title: "Segunda")])

        XCTAssertEqual(try storage.load().items.map(\.title), ["Segunda"])
    }

    func testSaveCreatesMissingIntermediateDirectories() throws {
        let nested = directory
            .appendingPathComponent("a/b/c", isDirectory: true)
            .appendingPathComponent("tasks.json")
        let deepStorage = TaskStorage(fileURL: nested)

        try deepStorage.save([TodoItem(title: "Honda")])

        XCTAssertEqual(try deepStorage.load().items.map(\.title), ["Honda"])
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

        XCTAssertEqual(raw?["version"] as? Int, 4, "subir la version es deliberado: obliga a pensar si los ficheros viejos siguen leyendose")
    }

    // MARK: - Migracion desde UserDefaults

    func testMigrationMovesLegacyBlobIntoFileAndDropsTheKey() throws {
        let defaults = UserDefaults(suiteName: suiteName)!
        let legacy = [TodoItem(title: "De UserDefaults")]
        // El blob viejo se escribia con un JSONEncoder sin configurar.
        defaults.set(try JSONEncoder().encode(legacy), forKey: "todo.items")

        let migrated = try storage.migrateLegacyDefaults(from: defaults, key: "todo.items")

        XCTAssertTrue(migrated)
        XCTAssertEqual(try storage.load().items.map(\.title), ["De UserDefaults"])
        XCTAssertNil(defaults.data(forKey: "todo.items"), "la clave vieja deberia quedar borrada")
    }

    func testMigrationDoesNothingWhenFileAlreadyExists() throws {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(try JSONEncoder().encode([TodoItem(title: "Vieja")]), forKey: "todo.items")
        try storage.save([TodoItem(title: "La del fichero")])

        let migrated = try storage.migrateLegacyDefaults(from: defaults, key: "todo.items")

        XCTAssertFalse(migrated)
        XCTAssertEqual(try storage.load().items.map(\.title), ["La del fichero"], "manda el fichero")
        XCTAssertNotNil(defaults.data(forKey: "todo.items"), "y no se toca la clave vieja")
    }

    func testMigrationIsANoOpWithoutLegacyData() throws {
        let defaults = UserDefaults(suiteName: suiteName)!

        XCTAssertFalse(try storage.migrateLegacyDefaults(from: defaults, key: "todo.items"))
        XCTAssertEqual(try storage.load().items, [])
    }

    // MARK: - Version 2: completedAt y archivo

    /// Un fichero de la version 1 traia isDone booleano y ninguna fecha de
    /// completado. Al convertirlo se usa lastModified como aproximacion.
    func testVersion1FileConvertsIsDoneIntoACompletionDate() throws {
        let hecha = #"{"id":"11111111-1111-1111-1111-111111111111","title":"Hecha en la v1","isDone":true,"lastModified":"2026-09-01T10:30:00.000Z"}"#
        let pendiente = #"{"id":"22222222-2222-2222-2222-222222222222","title":"Pendiente en la v1","isDone":false,"lastModified":"2026-09-01T10:30:00.000Z"}"#
        let json = #"{"version":1,"items":["# + hecha + "," + pendiente + "]}"
        try Data(json.utf8).write(to: storage.fileURL)

        let items = try storage.load().items

        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0].isDone)
        XCTAssertEqual(items[0].completedAt, items[0].lastModified)
        XCTAssertFalse(items[1].isDone)
        XCTAssertNil(items[1].completedAt)
    }

    /// Sin createdAt en el fichero viejo, la fecha de creacion tambien sale
    /// de lastModified.
    func testVersion1FileFallsBackToLastModifiedAsCreationDate() throws {
        let json = #"{"version":1,"items":[{"id":"33333333-3333-3333-3333-333333333333","title":"Sin createdAt","isDone":false,"lastModified":"2026-08-15T08:00:00.000Z"}]}"#
        try Data(json.utf8).write(to: storage.fileURL)

        let item = try XCTUnwrap(try storage.load().items.first)

        XCTAssertEqual(item.createdAt, item.lastModified)
    }

    func testArchivedTasksRoundTripSeparatelyFromActiveOnes() throws {
        var archivedItem = TodoItem(title: "Archivada")
        archivedItem.createdAt = Date(timeIntervalSince1970: 1_699_000_000.000)
        archivedItem.completedAt = Date(timeIntervalSince1970: 1_700_000_000.000)
        archivedItem.archivedAt = Date(timeIntervalSince1970: 1_700_000_100.000)
        archivedItem.lastModified = Date(timeIntervalSince1970: 1_700_000_100.000)

        try storage.save([TodoItem(title: "Activa")], archived: [archivedItem])

        let file = try storage.load()
        XCTAssertEqual(file.items.map(\.title), ["Activa"])
        XCTAssertEqual(file.archived, [archivedItem])
    }

    /// isDone es una fachada sobre completedAt y no debe llegar al fichero:
    /// si se escribiera, un lector antiguo se creeria al dia.
    func testSavedFileDoesNotWriteTheLegacyIsDoneField() throws {
        var item = TodoItem(title: "Hecha")
        item.isDone = true
        try storage.save([item])

        let text = try String(contentsOf: storage.fileURL, encoding: .utf8)

        XCTAssertTrue(text.contains("completedAt"))
        XCTAssertFalse(text.contains("isDone"))
    }
}

extension TaskStorageTests {
    // MARK: - Version 3: listas

    func testListAssignmentRoundTrips() throws {
        var item = TodoItem(title: "De trabajo")
        item.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        item.lastModified = item.createdAt
        item.listIdentifier = "CAL-123"
        item.listTitle = "Work"

        try storage.save([item])

        XCTAssertEqual(try storage.load().items, [item])
    }

    /// Los ficheros anteriores no traen lista, y eso no es un error: significa
    /// la lista por defecto.
    func testVersion2FileWithoutAListLoadsWithNone() throws {
        let json = #"{"version":2,"items":[{"id":"44444444-4444-4444-4444-444444444444","title":"Sin lista","createdAt":"2026-08-15T08:00:00.000Z","lastModified":"2026-08-15T08:00:00.000Z"}]}"#
        try Data(json.utf8).write(to: storage.fileURL)

        let item = try XCTUnwrap(try storage.load().items.first)

        XCTAssertNil(item.listIdentifier)
        XCTAssertNil(item.listTitle)
        XCTAssertEqual(item.title, "Sin lista")
    }
}
