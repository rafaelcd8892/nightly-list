import XCTest
@testable import NightlyList

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
        XCTAssertTrue(markdown.contains("## Done (1)"))
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

        XCTAssertTrue(markdown.contains("_Nothing completed._"))
        XCTAssertFalse(markdown.contains("Still open"))
    }
}

extension DayReportTests {
    /// El export va siempre en ingles, con locale fijo, para que no salga
    /// mezclado segun el idioma del Mac.
    func testMarkdownHeaderIsAlwaysEnglish() {
        let report = DayReport(day: today, items: [task("Algo")], calendar: calendar)

        XCTAssertTrue(
            report.markdown().hasPrefix("# January 15, 2027"),
            "cabecera inesperada: \(report.markdown().prefix(40))"
        )
    }
}

extension DayReportTests {
    // MARK: - Agrupacion por ticket

    func testMarkdownGroupsCompletedByTicket() {
        let report = DayReport(
            day: today,
            items: [
                task("Fix login ABC-1", completed: today),
                task("Review ABC-1 PR", completed: today),
                task("Ship XYZ-9", completed: today),
            ],
            calendar: calendar
        )

        let markdown = report.markdown(prompt: "-")

        XCTAssertTrue(markdown.contains("### ABC-1 (2)"))
        XCTAssertTrue(markdown.contains("### XYZ-9 (1)"))
    }

    /// Sin referencias no se agrupa: un encabezado de grupo no aportaria nada.
    func testMarkdownStaysFlatWithoutAnyTicket() {
        let report = DayReport(
            day: today,
            items: [task("Regar las plantas", completed: today)],
            calendar: calendar
        )

        let markdown = report.markdown(prompt: "-")

        XCTAssertFalse(markdown.contains("###"))
        XCTAssertTrue(markdown.contains("- [x] Regar las plantas"))
    }

    /// Mezcla: las que llevan referencia van agrupadas y el resto al final.
    func testTasksWithoutATicketGoLastUnderTheirOwnHeading() {
        let report = DayReport(
            day: today,
            items: [
                task("Sin referencia", completed: today),
                task("Con ABC-2", completed: today),
            ],
            calendar: calendar
        )

        let markdown = report.markdown(prompt: "-")
        let ticketHeading = try! XCTUnwrap(markdown.range(of: "### ABC-2"))
        let otherHeading = try! XCTUnwrap(markdown.range(of: "### No ticket"))

        XCTAssertTrue(ticketHeading.lowerBound < otherHeading.lowerBound)
    }

    func testGroupedSortsTicketsAlphabeticallyAndPutsTheRestAtTheEnd() {
        let groups = DayReport.grouped([
            task("Sin nada"),
            task("De XYZ-1"),
            task("De ABC-1"),
        ])

        XCTAssertEqual(groups.map(\.reference), ["ABC-1", "XYZ-1", nil])
    }

    /// Un titulo con dos referencias cuenta una sola vez, bajo la primera.
    func testATaskWithTwoReferencesIsNotCountedTwice() {
        let groups = DayReport.grouped([task("Cierra ABC-1 y XYZ-2")])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.reference, "ABC-1")
    }

    func testStillOpenSectionIsGroupedToo() {
        let report = DayReport(
            day: today,
            items: [task("Pendiente de ABC-5")],
            calendar: calendar
        )

        XCTAssertTrue(report.markdown(prompt: "-").contains("### ABC-5 (1)"))
    }
}

extension DayReportTests {
    /// La vista quiere lo ultimo arriba; el export cuenta el dia de principio
    /// a fin.
    func testExportListsCompletedChronologicallyEvenThoughTheViewIsReversed() {
        let report = DayReport(
            day: today,
            items: [
                task("Temprano", completed: today),
                task("Tarde", completed: today.addingTimeInterval(3_600)),
            ],
            calendar: calendar
        )

        XCTAssertEqual(report.completed.map(\.title), ["Tarde", "Temprano"], "la vista")

        let markdown = report.markdown(prompt: "-")
        let temprano = try! XCTUnwrap(markdown.range(of: "Temprano"))
        let tarde = try! XCTUnwrap(markdown.range(of: "Tarde"))
        XCTAssertTrue(temprano.lowerBound < tarde.lowerBound, "el export")
    }

    // MARK: - Notas en el export

    func testMarkdownIndentsTheNotesUnderTheirTask() {
        var item = TodoItem(title: "Arreglar el login")
        item.completedAt = Date()
        item.notes = "Era el refresh del token"

        let markdown = DayReport(items: [item]).markdown(prompt: "")

        XCTAssertTrue(markdown.contains("- [x] Arreglar el login"))
        XCTAssertTrue(
            markdown.contains("\n  Era el refresh del token"),
            "la nota va sangrada para seguir siendo el mismo punto de la lista"
        )
    }

    func testMarkdownKeepsMultiLineNotesTogether() {
        var item = TodoItem(title: "Arreglar el login")
        item.completedAt = Date()
        item.notes = "Primera\nSegunda"

        let markdown = DayReport(items: [item]).markdown(prompt: "")

        XCTAssertTrue(markdown.contains("  Primera\n  Segunda"))
    }

    func testMarkdownIgnoresBlankNotes() {
        var item = TodoItem(title: "Arreglar el login")
        item.completedAt = Date()
        item.notes = "   "

        let markdown = DayReport(items: [item]).markdown(prompt: "")

        XCTAssertFalse(markdown.contains("- [x] Arreglar el login\n  "))
    }
}
