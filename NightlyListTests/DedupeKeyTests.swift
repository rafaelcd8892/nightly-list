import XCTest
@testable import NightlyList

/// La regla de deduplicacion ha fallado tres veces: primero fundiendo tareas
/// de listas distintas, luego fundiendo completadas en dias distintos, y
/// despues dejando sin clave a todas las completadas, que es por donde se
/// colaron cuatrocientas copias de la misma nota. Por eso la decision vive en
/// una funcion pura y tiene sus propios tests.
final class DedupeKeyTests: XCTestCase {
    private func key(_ title: String, list: String = "L1", completedAt: Date? = nil) -> String? {
        RemindersSync.dedupeKey(listID: list, title: title, completedAt: completedAt)
    }

    private let martes = Date(timeIntervalSince1970: 1_757_000_000)

    // MARK: - Lo que si se deduplica

    func testTwoPendingTasksWithTheSameTitleInTheSameListMatch() {
        XCTAssertEqual(key("Comprar leche"), key("Comprar leche"))
    }

    func testTitlesAreComparedWithoutCaseAccentsOrStraySpaces() {
        XCTAssertEqual(key("  comprar LECHE "), key("Comprar leché"))
    }

    /// El caso que rompio la app: la sincronizacion creaba la misma nota una y
    /// otra vez, todas con la misma hora de completado.
    func testTwoTasksCompletedAtTheSameInstantMatch() {
        XCTAssertEqual(
            key("Comprar leche", completedAt: martes),
            key("Comprar leche", completedAt: martes)
        )
    }

    /// La copia local guarda decimales y EventKit no. Si el segundo es el
    /// mismo, son la misma cosa.
    func testSubSecondDifferencesStillMatch() {
        XCTAssertEqual(
            key("Comprar leche", completedAt: martes),
            key("Comprar leche", completedAt: martes.addingTimeInterval(0.523))
        )
    }

    // MARK: - Lo que no

    /// El mismo titulo en dos listas son dos tareas legitimas.
    func testTheSameTitleInDifferentListsDoesNotMatch() {
        XCTAssertNotEqual(key("Revisar", list: "Work"), key("Revisar", list: "Home"))
    }

    /// Comprar leche tres martes distintos son tres hechos, no un duplicado.
    /// Esto es lo que el historial existe para guardar.
    func testTheSameTitleCompletedOnDifferentDaysDoesNotMatch() {
        XCTAssertNotEqual(
            key("Comprar leche", completedAt: martes),
            key("Comprar leche", completedAt: martes.addingTimeInterval(7 * 24 * 3600))
        )
    }

    func testTheSameTitleCompletedASecondApartDoesNotMatch() {
        XCTAssertNotEqual(
            key("Comprar leche", completedAt: martes),
            key("Comprar leche", completedAt: martes.addingTimeInterval(1))
        )
    }

    /// Y una pendiente no se funde con una completada del mismo titulo: la
    /// pendiente es trabajo por hacer, la completada es historial.
    func testAPendingTaskDoesNotMatchACompletedOne() {
        XCTAssertNotEqual(key("Comprar leche"), key("Comprar leche", completedAt: martes))
    }

    /// Ya no hay tarea sin clave: sin clave no hay duplicado que detectar.
    func testEveryTaskGetsAKey() {
        XCTAssertNotNil(key("Comprar leche"))
        XCTAssertNotNil(key("Comprar leche", completedAt: martes))
    }
}
