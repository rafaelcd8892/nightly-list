import SwiftUI

/// Una lista de tareas, que en EventKit es un EKCalendar.
struct TaskList: Identifiable, Equatable {
    /// El calendarIdentifier del EKCalendar.
    let id: String
    let title: String
    let color: Color

    /// Lo que se enseña cuando una tarea no tiene lista asignada todavia.
    static let unassignedTitle = "No list"
}
