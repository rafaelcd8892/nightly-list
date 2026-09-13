import Foundation

/// El prompt que acompaña al export del dia.
///
/// Es editable y se guarda, porque la redaccion que le sirve a cada uno
/// depende de para que quiera el resumen: un daily, una factura, un diario.
enum SummaryPrompt {
    static let defaultText = """
        Summarize my day from the list above. Three or four sentences, no \
        bullet points. Group by theme instead of repeating the list, say what \
        was left unfinished, and do not invent anything that is not there. If \
        the list is empty, say so and do not pad it.
        """

    private static let key = "day.summaryPrompt"

    /// El guardado si hay uno util, y si no el de fabrica. Un prompt en
    /// blanco no cuenta: dejaria el export sin instrucciones.
    static var current: String {
        guard let stored = UserDefaults.standard.string(forKey: key),
              !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return defaultText }
        return stored
    }

    static var isCustomized: Bool {
        current != defaultText
    }

    static func save(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == defaultText {
            reset()
        } else {
            UserDefaults.standard.set(trimmed, forKey: key)
        }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
