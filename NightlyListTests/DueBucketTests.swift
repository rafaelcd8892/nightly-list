import XCTest
@testable import NightlyList

final class DueBucketTests: XCTestCase {
    /// Calendario fijo en UTC: si no, el resultado cambia segun donde se
    /// ejecute el test.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Mediodia, para que sumar y restar horas no cruce la medianoche sin
    /// querer.
    private let now = Date(timeIntervalSince1970: 1_800_043_200)  // 2027-01-15 12:00 UTC

    private func task(due: Date?) -> TodoItem {
        var item = TodoItem(title: "Cualquiera")
        item.dueDate = due
        return item
    }

    private func bucket(_ offsetDays: Double) -> DueBucket {
        DueBucket.of(task(due: now.addingTimeInterval(offsetDays * 86_400)), now: now, calendar: calendar)
    }

    func testATaskWithoutADateHasNoBucket() {
        XCTAssertEqual(DueBucket.of(task(due: nil), now: now, calendar: calendar), .noDate)
    }

    func testYesterdayIsOverdue() {
        XCTAssertEqual(bucket(-1), .overdue)
    }

    /// Vencida es antes del comienzo de hoy, no antes de ahora: algo para hoy
    /// a las nueve de la mañana no esta vencido a mediodia, esta para hoy.
    func testEarlierTodayIsStillToday() {
        let esta_manana = now.addingTimeInterval(-3 * 3_600)

        XCTAssertEqual(DueBucket.of(task(due: esta_manana), now: now, calendar: calendar), .today)
    }

    func testLaterTodayIsToday() {
        XCTAssertEqual(DueBucket.of(task(due: now.addingTimeInterval(3_600)), now: now, calendar: calendar), .today)
    }

    func testTomorrowIsTomorrow() {
        XCTAssertEqual(bucket(1), .tomorrow)
    }

    func testTheDayAfterTomorrowIsThisWeek() {
        XCTAssertEqual(bucket(2), .thisWeek)
    }

    func testSixDaysOutIsStillThisWeek() {
        XCTAssertEqual(bucket(6), .thisWeek)
    }

    func testAWeekOutIsLater() {
        XCTAssertEqual(bucket(8), .later)
    }

    /// El orden del enum es el orden en que se pintan las secciones.
    func testBucketsAreOrderedFromMostUrgentToLeast() {
        XCTAssertEqual(
            DueBucket.allCases,
            [.overdue, .today, .tomorrow, .thisWeek, .later, .noDate]
        )
        XCTAssertLessThan(DueBucket.overdue, DueBucket.noDate)
    }
}
