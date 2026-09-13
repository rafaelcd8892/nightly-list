import Foundation

/// La prioridad de una tarea, con los mismos cuatro escalones que enseña la
/// app Recordatorios.
///
/// Por debajo es el campo `priority` de EKReminder, que es un entero de 0 a 9
/// definido por el RFC 5545: 0 sin prioridad, 1-4 alta, 5 media, 6-9 baja. La
/// tarea guarda el entero crudo y no este enum, para devolverle a Recordatorios
/// exactamente el numero que trajo; esto es solo como se lee y como se escribe
/// desde la interfaz.
enum TaskPriority: Int, CaseIterable, Identifiable, Codable {
    case none = 0
    case high = 1
    case medium = 5
    case low = 9

    var id: Int { rawValue }

    /// Traduce cualquier entero del rango del RFC al escalon que le toca.
    init(rawPriority: Int) {
        switch rawPriority {
        case 1...4: self = .high
        case 5: self = .medium
        case 6...9: self = .low
        default: self = .none
        }
    }

    var title: String {
        switch self {
        case .none: return "None"
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }

    /// Como se lee en un menu: "High  !!!".
    var menuTitle: String {
        marker.isEmpty ? title : "\(title)  \(marker)"
    }

    /// El distintivo de Recordatorios: una admiracion por escalon.
    var marker: String {
        switch self {
        case .none: return ""
        case .high: return "!!!"
        case .medium: return "!!"
        case .low: return "!"
        }
    }
}
