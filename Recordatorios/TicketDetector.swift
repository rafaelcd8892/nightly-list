import Foundation

/// Encuentra referencias de proyecto o ticket tipo ABC-123 en el texto de una
/// tarea.
///
/// Sin configuracion: detecta por forma, no por una lista de proyectos que
/// haya que mantener. Exigir mayusculas es lo que hace el trabajo sucio —
/// descarta las palabras con guion normales y las fechas como 2026-09-13, que
/// no empiezan por letra.
enum TicketDetector {
    /// Letra inicial, de dos a diez caracteres de clave, guion y hasta seis
    /// digitos. El limite de digitos evita tragarse numeros largos que no son
    /// un ticket.
    private static let pattern = /\b([A-Z][A-Z0-9]{1,9})-([0-9]{1,6})\b/

    /// Las claves encontradas, sin repetir y en el orden en que aparecen.
    static func keys(in text: String) -> [String] {
        var found: [String] = []
        for match in text.matches(of: pattern) {
            let key = String(match.1)
            if !found.contains(key) {
                found.append(key)
            }
        }
        return found
    }

    /// Las referencias completas, con su numero.
    static func references(in text: String) -> [String] {
        var found: [String] = []
        for match in text.matches(of: pattern) {
            let reference = String(match.0)
            if !found.contains(reference) {
                found.append(reference)
            }
        }
        return found
    }
}

extension TodoItem {
    /// La referencia por la que se agrupa esta tarea. Si el titulo lleva
    /// varias se usa la primera, para no contar la tarea dos veces.
    var ticketReference: String? {
        TicketDetector.references(in: title).first
    }
}
