import XCTest
@testable import NightlyList

/// La regla de deduplicacion ha fallado dos veces: primero fundiendo tareas de
/// listas distintas, luego fundiendo completadas en dias distintos. Por eso la
/// decision vive en una funcion pura y tiene sus propios tests.
final class DedupeKeyTests: XCTestCase {
    private func key(_ title: String, list: String = "L1", completed: Bool = false) -> String? {
        RemindersSync.dedupeKey(listID: list, title: title, isCompleted: completed)
    }

    // MARK: - Lo que si se deduplica

    func testTwoPendingTasksWithTheSameTitleInTheSameListMatch() {
        XCTAssertEqual(key("Comprar leche"), key("Comprar leche"))
    }

    func testTitlesAreComparedWithoutCaseAccentsOrStraySpaces() {
        XCTAssertEqual(key("  comprar LECHE "), key("Comprar leché"))
    }

    // MARK: - Lo que no

    /// El mismo titulo en dos listas son dos tareas legitimas.
    func testTheSameTitleInDifferentListsDoesNotMatch() {
        XCTAssertNotEqual(key("Revisar", list: "Work"), key("Revisar", list: "Home"))
    }

    /// Comprar leche tres martes distintos son tres hechos, no un duplicado.
    /// Una completada no tiene clave, asi que nunca se funde con nada.
    func testCompletedTasksNeverGetAKey() {
        XCTAssertNil(key("Comprar leche", completed: true))
    }

    func testTwoCompletedTasksWithTheSameTitleDoNotMatch() {
        let first = key("Comprar leche", completed: true)
        let second = key("Comprar leche", completed: true)

        XCTAssertNil(first)
        XCTAssertNil(second)
    }

    /// Y una pendiente no se funde con una completada del mismo titulo: la
    /// pendiente es trabajo por hacer, la completada es historial.
    func testAPendingTaskDoesNotMatchACompletedOne() {
        XCTAssertNotNil(key("Comprar leche"))
        XCTAssertNil(key("Comprar leche", completed: true))
    }
}
