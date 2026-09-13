import Combine
import Foundation
import os

/// Registro de diagnostico de la app.
///
/// Escribe una linea por evento en un fichero que el usuario puede exportar
/// desde Ajustes, y lo espeja en el log unificado del sistema. El fichero es
/// lo que sirve para pedir "mandame el log": sobrevive a los reinicios, cosa
/// que os_log por si solo no garantiza.
@MainActor
final class DiagnosticLog: ObservableObject {
    static let shared = DiagnosticLog()

    enum Category: String {
        case app = "app"
        case storage = "storage"
        case notifications = "notifications"
        case sync = "sync"
        case login = "login"
    }

    /// Cuando el fichero pasa de aqui se recorta por la cabeza. Sin tope, un
    /// bucle de sincronizacion lo dejaria en cientos de megas.
    private static let maxBytes = 256 * 1024

    /// Cambia con cada escritura para que la vista de Ajustes se entere.
    @Published private(set) var revision = 0

    private let logger = Logger(subsystem: "rafaelcd8892.Recordatorios", category: "diagnostico")
    let fileURL: URL?

    private init() {
        fileURL = try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Recordatorios", isDirectory: true)
            .appendingPathComponent("diagnostico.log", isDirectory: false)
    }

    func log(_ category: Category, _ message: String) {
        logger.log("[\(category.rawValue, privacy: .public)] \(message, privacy: .public)")
        append("\(Self.timestamp.string(from: Date()))  [\(category.rawValue)]  \(message)")
    }

    /// Todo el contenido del fichero, para enseñarlo o copiarlo.
    func readAll() -> String {
        guard let fileURL, let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return ""
        }
        return text
    }

    func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
        revision += 1
    }

    private func append(_ line: String) {
        guard let fileURL, !Self.isRunningTests else { return }
        defer { revision += 1 }

        do {
            let data = Data((line + "\n").utf8)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: fileURL)
            }
            trimIfNeeded()
        } catch {
            // Si el fichero no se deja escribir, al menos queda en el log del
            // sistema. No tiene sentido avisar al usuario de que fallo el log.
            logger.error("Could not write the log: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Se queda con la mitad mas reciente. Recortar por la cabeza y no borrar
    /// entero deja siempre algo de contexto de lo que acaba de pasar.
    private func trimIfNeeded() {
        guard let fileURL,
              let size = try? FileManager.default
                  .attributesOfItem(atPath: fileURL.path)[.size] as? Int,
              size > Self.maxBytes,
              let text = try? String(contentsOf: fileURL, encoding: .utf8)
        else { return }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let kept = lines.suffix(lines.count / 2).joined(separator: "\n")
        try? Data(kept.utf8).write(to: fileURL, options: .atomic)
    }

    /// Locale POSIX obligatorio: con un dateFormat fijo, el idioma del
    /// usuario puede reescribirlo. Con un Mac en 12 horas, "HH" salia como
    /// "7:41 PM".
    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// Los tests corren hospedados en la app y comparten su contenedor: sin
    /// esto, cada pasada ensucia el registro real del usuario.
    private static let isRunningTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
