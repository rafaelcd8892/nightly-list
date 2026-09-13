import SwiftUI

/// Una lista de tareas, que en EventKit es un EKCalendar.
struct TaskList: Identifiable, Equatable {
    /// El calendarIdentifier del EKCalendar.
    let id: String
    let title: String
    let color: Color

    /// Lo que se enseña cuando una tarea no tiene lista asignada todavia.
    static let unassignedTitle = "No list"

    /// El color de la lista como imagen no-plantilla.
    ///
    /// Dentro de un menu, un Image(systemName:) se pinta como plantilla y
    /// pierde el color: por eso los puntos salian todos grises. Una NSImage
    /// con isTemplate en false si conserva el suyo.
    var dotImage: NSImage {
        let lado = 10.0
        let image = NSImage(size: NSSize(width: lado, height: lado))
        image.lockFocus()
        NSColor(color).setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: lado, height: lado)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
