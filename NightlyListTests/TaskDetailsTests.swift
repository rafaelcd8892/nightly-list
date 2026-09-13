import EventKit
import XCTest
@testable import NightlyList

/// Notas, prioridad, URL y repeticion: los campos que la sincronizacion
/// tiraba en silencio.
final class TaskDetailsTests: XCTestCase {

    // MARK: - Prioridad

    func testPriorityBucketsTheRFCRange() {
        XCTAssertEqual(TaskPriority(rawPriority: 0), .none)
        XCTAssertEqual(TaskPriority(rawPriority: 1), .high)
        XCTAssertEqual(TaskPriority(rawPriority: 4), .high)
        XCTAssertEqual(TaskPriority(rawPriority: 5), .medium)
        XCTAssertEqual(TaskPriority(rawPriority: 6), .low)
        XCTAssertEqual(TaskPriority(rawPriority: 9), .low)
    }

    func testUnknownPriorityReadsAsNone() {
        // Fuera del rango del RFC no hay escalon que valga; mejor ninguno que
        // inventarse uno.
        XCTAssertEqual(TaskPriority(rawPriority: 42), .none)
        XCTAssertEqual(TaskPriority(rawPriority: -1), .none)
    }

    func testWritingPriorityKeepsTheRawValueRoundTrippable() {
        var item = TodoItem(title: "Cualquiera")
        XCTAssertEqual(item.priority, .none)
        XCTAssertNil(item.priorityValue, "sin tocarla no hay opinion sobre la prioridad")

        item.priority = .high
        XCTAssertEqual(item.priorityValue, 1)
        XCTAssertEqual(item.priority, .high)
    }

    func testPriorityFromRemindersSurvivesUntouched() {
        // Un 3 es alta para el RFC pero no es ninguno de nuestros cuatro
        // valores. Si no se toca, vuelve a Recordatorios tal cual.
        var item = TodoItem(title: "Cualquiera")
        item.priorityValue = 3
        XCTAssertEqual(item.priority, .high)
        XCTAssertEqual(item.priorityValue, 3)
    }

    // MARK: - URL

    func testURLReadsAndWritesThroughTheRawString() {
        var item = TodoItem(title: "Cualquiera")
        XCTAssertNil(item.url)

        item.urlString = "https://example.com/ABC-123"
        XCTAssertEqual(item.url?.absoluteString, "https://example.com/ABC-123")

        // Borrarla deja cadena vacia, no nil: vaciarla es una opinion y tiene
        // que llegar a Recordatorios.
        item.url = nil
        XCTAssertEqual(item.urlString, "")
        XCTAssertNil(item.url)
    }

    func testBlankURLTextIsNotAURL() {
        var item = TodoItem(title: "Cualquiera")
        item.urlString = "   "
        XCTAssertNil(item.url)
    }

    // MARK: - Notas

    func testHasNotesIgnoresWhitespace() {
        var item = TodoItem(title: "Cualquiera")
        XCTAssertFalse(item.hasNotes)

        item.notes = "  \n "
        XCTAssertFalse(item.hasNotes)

        item.notes = "Se rompio el refresh del token"
        XCTAssertTrue(item.hasNotes)
    }

    // MARK: - Adoptar lo que la tarea no sabe

    /// La regla que evita que actualizar la app borre las notas de todos los
    /// recordatorios que ya existian.
    func testUnknownFieldsAreAdoptedFromTheReminder() {
        let reminder = makeReminder()
        reminder.notes = "Lo que escribio el usuario en Recordatorios"
        reminder.priority = 5
        reminder.url = URL(string: "https://example.com")

        var item = TodoItem(title: "Cualquiera")
        XCTAssertNil(item.notes, "una tarea de antes de la version 4 no sabe nada de esto")

        let changed = RemindersSync.adoptUnknownDetails(of: reminder, into: &item)

        XCTAssertTrue(changed)
        XCTAssertEqual(item.notes, "Lo que escribio el usuario en Recordatorios")
        XCTAssertEqual(item.priorityValue, 5)
        XCTAssertEqual(item.urlString, "https://example.com")
    }

    func testKnownFieldsAreNotOverwrittenWhenAdopting() {
        let reminder = makeReminder()
        reminder.notes = "Lo de Recordatorios"
        reminder.priority = 9

        var item = TodoItem(title: "Cualquiera")
        item.notes = "Lo que escribi aqui"
        item.priorityValue = 1

        _ = RemindersSync.adoptUnknownDetails(of: reminder, into: &item)

        XCTAssertEqual(item.notes, "Lo que escribi aqui")
        XCTAssertEqual(item.priorityValue, 1)
    }

    func testAdoptingReportsNoChangeWhenThereIsNothingNew() {
        let reminder = makeReminder()
        var item = TodoItem(title: "Cualquiera")
        _ = RemindersSync.adoptUnknownDetails(of: reminder, into: &item)

        XCTAssertFalse(
            RemindersSync.adoptUnknownDetails(of: reminder, into: &item),
            "sin cambios no hay que reescribir la lista, que dispara otra sincronizacion"
        )
    }

    func testDeletingNotesLocallyIsAnOpinionAndSurvivesAdoption() {
        let reminder = makeReminder()
        reminder.notes = "Lo de Recordatorios"

        var item = TodoItem(title: "Cualquiera")
        item.notes = ""

        _ = RemindersSync.adoptUnknownDetails(of: reminder, into: &item)

        XCTAssertEqual(item.notes, "", "vacio no es lo mismo que nil")
    }

    // MARK: - Repeticion

    func testRecurrenceSummaryReadsTheRule() {
        XCTAssertEqual(
            RemindersSync.summary(of: EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)),
            "Every day"
        )
        XCTAssertEqual(
            RemindersSync.summary(of: EKRecurrenceRule(recurrenceWith: .weekly, interval: 2, end: nil)),
            "Every 2 weeks"
        )
        XCTAssertEqual(
            RemindersSync.summary(of: EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)),
            "Every month"
        )
        XCTAssertEqual(
            RemindersSync.summary(of: EKRecurrenceRule(recurrenceWith: .yearly, interval: 3, end: nil)),
            "Every 3 years"
        )
    }

    func testNonRepeatingReminderHasNoSummary() {
        XCTAssertNil(RemindersSync.recurrenceSummary(of: makeReminder()))
        XCTAssertFalse(TodoItem(title: "Cualquiera").isRecurring)
    }

    // MARK: - Persistencia

    func testDetailsSurviveAJSONRoundTrip() throws {
        var item = TodoItem(title: "Arreglar ABC-123")
        item.notes = "Dos lineas\ny la segunda"
        item.priorityValue = 5
        item.urlString = "https://example.com/ABC-123"
        item.recurrenceSummary = "Every week"

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(TodoItem.self, from: data)

        XCTAssertEqual(decoded.notes, item.notes)
        XCTAssertEqual(decoded.priorityValue, 5)
        XCTAssertEqual(decoded.urlString, item.urlString)
        XCTAssertEqual(decoded.recurrenceSummary, "Every week")
    }

    func testFilesFromBeforeVersion4ReadWithoutOpinions() throws {
        let legacy = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Una tarea de antes",
          "createdAt": "2026-09-01T10:00:00Z",
          "lastModified": "2026-09-01T10:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let item = try decoder.decode(TodoItem.self, from: Data(legacy.utf8))

        XCTAssertEqual(item.title, "Una tarea de antes")
        XCTAssertNil(item.notes)
        XCTAssertNil(item.priorityValue)
        XCTAssertNil(item.urlString)
        XCTAssertNil(item.recurrenceSummary)
    }

    // MARK: - Helpers

    /// Un EKReminder suelto, sin guardar y sin pedir permisos: solo hace falta
    /// el objeto para leerle los campos.
    private func makeReminder() -> EKReminder {
        EKReminder(eventStore: EKEventStore())
    }
}
