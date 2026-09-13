import XCTest
@testable import Recordatorios

final class DayReportTests: XCTestCase {
    /// Calendario fijo en UTC: si no, el test cambia de resultado segun donde
    /// se ejecute.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let today = Date(timeIntervalSince1970: 1_800_000_000)      // 2027-01-15 08:00 UTC
    private lazy var yesterday = today.addingTimeInterval(-86_400)

    private func task(
        _ title: String,
        created: Date? = nil,
        completed: Date? = nil
    ) -> TodoItem {
        var item = TodoItem(title: title)
        item.createdAt = created ?? today
        item.completedAt = completed
        return item
    }

    // MARK: - Que entra en el dia

    func testCompletedTodayGoesIntoTheReport() {
        let report = DayReport(
            day: today,
            items: [task("Hecha hoy", completed: today)],
            calendar: calendar
        )

        XCTAssertEqual(report.completed.map(\.title), ["Hecha hoy"])
    }

    func testCompletedYesterdayIsLeftOut() {
        let report = DayReport(
            day: today,
            items: [task("Hecha ayer", created: yesterday, completed: yesterday)],
            calendar: calendar
        )

        XCTAssertTrue(report.isEmpty)
    }

    func testCreatedTodayAndStillOpenGoesIntoCreated() {
        let report = DayReport(
            day: today,
            items: [task("Apuntada hoy")],
            calendar: calendar
        )

        XCTAssertEqual(report.created.map(\.title), ["Apuntada hoy"])
        XCTAssertTrue(report.completed.isEmpty)
    }

    /// Creada y cerrada el mismo dia cuenta una vez, como hecha.
    func testCreatedAndCompletedTheSameDayIsNotCountedTwice() {
        let report = DayReport(
            day: today,
            items: [task("Del tiron", completed: today)],
            calendar: calendar
        )

        XCTAssertEqual(report.completed.map(\.title), ["Del tiron"])
        XCTAssertTrue(report.created.isEmpty)
    }

    /// Lo archivado sigue siendo actividad del dia: "Limpiar hechas" no debe
    /// vaciar el registro.
    func testArchivedTasksStillCountForTheDay() {
        var archivedItem = task("Archivada", completed: today)
        archivedItem.archivedAt = today

        let report = DayReport(
            day: today,
            items: [],
            archived: [archivedItem],
            calendar: calendar
        )

        XCTAssertEqual(report.completed.map(\.title), ["Archivada"])
    }

    func testCompletedAreSortedMostRecentFirst() {
        let report = DayReport(
            day: today,
            items: [
                task("Temprano", completed: today),
                task("Tarde", completed: today.addingTimeInterval(3_600)),
            ],
            calendar: calendar
        )

        XCTAssertEqual(report.completed.map(\.title), ["Tarde", "Temprano"])
    }

    // MARK: - Markdown

    func testMarkdownListsBothSectionsAndCarriesThePrompt() {
        let report = DayReport(
            day: today,
            items: [task("Cerrada", completed: today), task("Abierta")],
            calendar: calendar
        )

        let markdown = report.markdown()

        XCTAssertTrue(markdown.contains("- [x] Cerrada"))
        XCTAssertTrue(markdown.contains("- [ ] Abierta"))
        XCTAssertTrue(markdown.contains("## Hecho (1)"))
        XCTAssertTrue(markdown.contains(SummaryPrompt.defaultText))
    }

    /// El prompt es editable, asi que el export tiene que llevar el que le
    /// pasen y no uno fijo.
    func testMarkdownCarriesTheGivenPrompt() {
        let report = DayReport(day: today, items: [task("Algo")], calendar: calendar)

        let markdown = report.markdown(prompt: "Dime solo cuantas quedaron a medias.")

        XCTAssertTrue(markdown.contains("Dime solo cuantas quedaron a medias."))
        XCTAssertFalse(markdown.contains(SummaryPrompt.defaultText))
    }

    func testMarkdownSaysSoWhenNothingWasCompleted() {
        let report = DayReport(day: today, items: [], calendar: calendar)

        let markdown = report.markdown()

        XCTAssertTrue(markdown.contains("_Nada completado._"))
        XCTAssertFalse(markdown.contains("Apuntado y sin cerrar"))
    }
}
