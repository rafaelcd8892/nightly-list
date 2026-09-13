import Carbon.HIToolbox

/// Atajo global via Carbon.
///
/// Se usa RegisterEventHotKey y no NSEvent.addGlobalMonitorForEvents porque
/// el monitor exige permiso de accesibilidad al usuario; este no, y funciona
/// dentro del sandbox.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var actions: [UInt32: () -> Void] = [:]
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    private init() {}

    /// Registra un atajo. `keyCode` es un kVK_* y `modifiers` una mascara
    /// Carbon (optionKey, cmdKey, …). Devuelve false si el sistema lo tiene
    /// cogido por otra app.
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1

        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: OSType(0x5243_4441), id: id),  // 'RCDA'
            GetEventDispatcherTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else { return false }
        actions[id] = action
        references[id] = reference
        return true
    }

    /// Suelta todos los atajos. Hace falta para poder cambiarlos: registrar
    /// uno nuevo sin soltar el anterior deja los dos activos.
    func unregisterAll() {
        for reference in references.values {
            UnregisterEventHotKey(reference)
        }
        references.removeAll()
        actions.removeAll()
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetEventDispatcherTarget(), hotKeyEventHandler, 1, &spec, nil, nil)
    }
}

/// El handler de Carbon es un puntero a funcion C: no puede capturar
/// contexto, asi que saca el id del evento y lo reenvia al singleton.
///
/// nonisolated es obligatorio: el proyecto compila con
/// -default-isolation=MainActor y una funcion aislada al main actor no se
/// puede convertir en puntero a funcion C.
private nonisolated func hotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let id = hotKeyID.id
    Task { @MainActor in HotKeyCenter.shared.fire(id) }
    return noErr
}
