import XCTest
@testable import NightlyList

final class TicketDetectorTests: XCTestCase {
    // MARK: - Lo que si es un ticket

    func testFindsASimpleReference() {
        XCTAssertEqual(TicketDetector.references(in: "Arreglar ABC-123"), ["ABC-123"])
    }

    func testFindsAReferenceAtTheStartAndAtTheEnd() {
        XCTAssertEqual(TicketDetector.references(in: "ABC-1 y luego XYZ-99"), ["ABC-1", "XYZ-99"])
    }

    func testFindsAKeyWithDigitsInIt() {
        XCTAssertEqual(TicketDetector.references(in: "Revisar A1B-22"), ["A1B-22"])
    }

    func testHandlesReferencesInsideParenthesesAndBrackets() {
        XCTAssertEqual(TicketDetector.references(in: "Cerrar (ABC-7) y [XYZ-8]"), ["ABC-7", "XYZ-8"])
    }

    func testDoesNotRepeatTheSameReference() {
        XCTAssertEqual(
            TicketDetector.references(in: "ABC-123 depende de ABC-123"),
            ["ABC-123"]
        )
    }

    func testKeysDropTheNumber() {
        XCTAssertEqual(TicketDetector.keys(in: "ABC-1 y ABC-2 y XYZ-3"), ["ABC", "XYZ"])
    }

    // MARK: - Lo que no

    /// Una fecha no empieza por letra, asi que no entra.
    func testIgnoresDates() {
        XCTAssertTrue(TicketDetector.references(in: "Entregar el 2026-09-13").isEmpty)
    }

    func testIgnoresLowercase() {
        XCTAssertTrue(TicketDetector.references(in: "mirar abc-123").isEmpty)
    }

    func testIgnoresASingleLetterPrefix() {
        XCTAssertTrue(TicketDetector.references(in: "Comprar A-4 para imprimir").isEmpty)
    }

    func testIgnoresTextWithoutAnyReference() {
        XCTAssertTrue(TicketDetector.references(in: "Regar las plantas").isEmpty)
    }

    func testIgnoresAHyphenWithoutDigits() {
        XCTAssertTrue(TicketDetector.references(in: "Revisar ABC-XYZ").isEmpty)
    }

    /// Documenta un falso positivo conocido y aceptado: UTF-8 tiene la misma
    /// forma que un ticket y no hay manera de distinguirlos por la forma. Se
    /// asume a cambio de no tener que configurar una lista de proyectos.
    func testKnownFalsePositiveOnThingsLikeUTF8() {
        XCTAssertEqual(TicketDetector.references(in: "Pasar el fichero a UTF-8"), ["UTF-8"])
    }

    // MARK: - En la tarea

    func testItemExposesItsFirstReference() {
        var item = TodoItem(title: "Cerrar ABC-1 antes de XYZ-2")

        XCTAssertEqual(item.ticketReference, "ABC-1")

        item.title = "Sin referencia"
        XCTAssertNil(item.ticketReference)
    }
}
