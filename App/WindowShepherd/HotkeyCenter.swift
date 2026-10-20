import Carbon.HIToolbox
import WindowShepherdCore

/// One global shortcut, registered with Carbon's RegisterEventHotKey. macOS
/// refuses keys the system owns, so a failed enable is logged, never fatal.
final class Hotkey {
    let combo: Combo
    fileprivate let id: UInt32
    private let code: UInt32
    private var ref: EventHotKeyRef?
    private var loggedFailure = false

    fileprivate init(combo: Combo, id: UInt32, code: UInt32) {
        self.combo = combo
        self.id = id
        self.code = code
    }

    var isEnabled: Bool { ref != nil }

    func enable() {
        guard ref == nil else { return }
        let hid = EventHotKeyID(signature: HotkeyCenter.signature, id: id)
        let status = RegisterEventHotKey(code, carbonModifiers(combo.mods), hid, GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            ref = nil
            if !loggedFailure { Log.info("couldn't bind \(combo.formatted) (error \(status))") }   // once, not on every resume
            loggedFailure = true
        }
    }

    func disable() {
        guard let r = ref else { return }
        UnregisterEventHotKey(r)
        ref = nil
    }

    func delete() {
        disable()
        HotkeyCenter.shared.forget(self)
    }
}

final class HotkeyCenter {
    static let shared = HotkeyCenter()
    static let signature: OSType = 0x5753_4850   // "WSHP"

    private var handlers: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hid = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        nil, MemoryLayout<EventHotKeyID>.size, nil, &hid)
            guard err == noErr, hid.signature == HotkeyCenter.signature else { return OSStatus(eventNotHandledErr) }
            HotkeyCenter.shared.fire(hid.id)
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// A disabled hotkey for `combo`, or nil (logged) if this keyboard has no such key.
    func register(_ combo: Combo, _ fn: @escaping () -> Void) -> Hotkey? {
        guard let code = KeyCodes.code(for: combo.key) else {
            Log.info("couldn't bind \(combo.formatted): this keyboard has no “\(combo.key)” key")
            return nil
        }
        let hk = Hotkey(combo: combo, id: nextID, code: code)
        handlers[nextID] = fn
        nextID += 1
        return hk
    }

    fileprivate func forget(_ hk: Hotkey) { handlers[hk.id] = nil }

    private func fire(_ id: UInt32) { handlers[id]?() }
}
