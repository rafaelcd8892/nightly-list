import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Captura una combinacion de teclas.
///
/// Es una NSView y no una vista de SwiftUI porque hay que leer el keyCode
/// crudo del evento: SwiftUI entrega el caracter ya interpretado, y Carbon
/// registra atajos por codigo de tecla.
struct ShortcutRecorder: NSViewRepresentable {
    let onCapture: (QuickCaptureShortcut) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.onCapture = onCapture
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
    }

    final class RecorderView: NSView {
        var onCapture: ((QuickCaptureShortcut) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            var carbon: UInt32 = 0
            var simbolos = ""
            if flags.contains(.control) { carbon |= UInt32(controlKey); simbolos += "⌃" }
            if flags.contains(.option) { carbon |= UInt32(optionKey); simbolos += "⌥" }
            if flags.contains(.shift) { carbon |= UInt32(shiftKey); simbolos += "⇧" }
            if flags.contains(.command) { carbon |= UInt32(cmdKey); simbolos += "⌘" }

            // Un atajo global sin modificadores se comeria esa tecla en todo el
            // sistema.
            guard carbon != 0 else {
                NSSound.beep()
                return
            }

            onCapture?(
                QuickCaptureShortcut(
                    keyCode: UInt32(event.keyCode),
                    carbonModifiers: carbon,
                    display: simbolos + Self.nombre(of: event)
                )
            )
        }

        private static func nombre(of event: NSEvent) -> String {
            switch Int(event.keyCode) {
            case kVK_Space: return "Space"
            case kVK_Return: return "↩"
            case kVK_Tab: return "⇥"
            case kVK_Delete: return "⌫"
            default:
                return event.charactersIgnoringModifiers?.uppercased() ?? "?"
            }
        }
    }
}
