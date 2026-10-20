import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Key names ↔ virtual key codes, following the current keyboard layout for
/// character keys (like Hammerspoon's hs.keycodes.map). Call from the main thread.
public enum KeyCodes {
    /// Keys whose code doesn't depend on the layout.
    private static let fixed: [String: UInt32] = [
        "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53, "forwarddelete": 117,
        "help": 114, "home": 115, "pageup": 116, "end": 119, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101,
        "f10": 109, "f11": 103, "f12": 111, "f13": 105, "f14": 107, "f15": 113, "f16": 106, "f17": 64,
        "f18": 79, "f19": 80, "f20": 90,
        "pad0": 82, "pad1": 83, "pad2": 84, "pad3": 85, "pad4": 86, "pad5": 87, "pad6": 88, "pad7": 89,
        "pad8": 91, "pad9": 92, "pad.": 65, "pad*": 67, "pad+": 69, "pad/": 75, "pad-": 78, "pad=": 81,
        "padenter": 76, "padclear": 71,
    ]

    private static var byName: [String: UInt32] = [:]
    private static var byCode: [UInt16: String] = [:]
    private static var loaded = false

    public static func code(for key: String) -> UInt32? {
        loadIfNeeded()
        return byName[key]
    }

    public static func name(for code: UInt16) -> String? {
        loadIfNeeded()
        return byCode[code]
    }

    /// Re-read the layout (after the user switches keyboard layouts).
    public static func reload() {
        loaded = false
        loadIfNeeded()
    }

    private static func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        var names: [String: UInt32] = fixed
        var codes: [UInt16: String] = [:]
        for (n, c) in fixed { codes[UInt16(c)] = n }
        let fixedCodes = Set(fixed.values)
        for code in UInt16(0)..<128 where !fixedCodes.contains(UInt32(code)) {
            guard let ch = character(for: code), !ch.isEmpty else { continue }
            let key = ch.lowercased()
            if names[key] == nil { names[key] = UInt32(code) }
            codes[code] = key
        }
        byName = names
        byCode = codes
    }

    /// The character a key types with no modifiers on the current layout.
    private static func character(for code: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
                ?? TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var dead: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var len = 0
            let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &len, &chars)
            guard status == noErr, len > 0 else { return nil }
            let s = String(utf16CodeUnits: chars, count: len)
            return s.unicodeScalars.allSatisfy({ $0.properties.generalCategory != .control }) ? s : nil
        }
    }
}

public func carbonModifiers(_ m: Set<Mod>) -> UInt32 {
    var out = 0
    if m.contains(.cmd) { out |= cmdKey }
    if m.contains(.shift) { out |= shiftKey }
    if m.contains(.alt) { out |= optionKey }
    if m.contains(.ctrl) { out |= controlKey }
    return UInt32(out)
}

public func mods(fromCarbon c: UInt32) -> Set<Mod> {
    var m = Set<Mod>()
    if c & UInt32(cmdKey) != 0 { m.insert(.cmd) }
    if c & UInt32(shiftKey) != 0 { m.insert(.shift) }
    if c & UInt32(optionKey) != 0 { m.insert(.alt) }
    if c & UInt32(controlKey) != 0 { m.insert(.ctrl) }
    return m
}

public func mods(fromCGFlags f: CGEventFlags) -> Set<Mod> {
    var m = Set<Mod>()
    if f.contains(.maskCommand) { m.insert(.cmd) }
    if f.contains(.maskShift) { m.insert(.shift) }
    if f.contains(.maskAlternate) { m.insert(.alt) }
    if f.contains(.maskControl) { m.insert(.ctrl) }
    return m
}
