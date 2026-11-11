import AppKit
import Carbon.HIToolbox

/// Atajo global sin permisos de accesibilidad (API de Carbon `RegisterEventHotKey`).
/// Por defecto ⌃⌥Espacio abre el selector rápido.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private static var instances: [UInt32: HotKey] = [:]
    private static var nextID: UInt32 = 1
    private let id: UInt32

    init?(keyCode: UInt32 = UInt32(kVK_Space), modifiers: UInt32 = UInt32(controlKey | optionKey), action: @escaping () -> Void) {
        self.action = action
        self.id = HotKey.nextID
        HotKey.nextID += 1

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            if err == noErr, let target = HotKey.instances[hk.id] {
                DispatchQueue.main.async { target.action() }
            }
            return noErr
        }, 1, &spec, nil, &handler)
        guard status == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4155_5241), id: id) // 'AURA'
        let reg = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard reg == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
        HotKey.instances[id] = self
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        HotKey.instances[id] = nil
    }
}
