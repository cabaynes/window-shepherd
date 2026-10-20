import Foundation

/// A modifier key. `allCases` is keyboard order, the order shortcuts are
/// always written in: ⌃ ⌥ ⌘ key ⇧ (Charles's rule).
public enum Mod: String, Codable, CaseIterable, Comparable {
    case ctrl, alt, cmd, shift

    public var symbol: String {
        switch self {
        case .ctrl: return "⌃"
        case .alt: return "⌥"
        case .cmd: return "⌘"
        case .shift: return "⇧"
        }
    }

    public static func < (a: Mod, b: Mod) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// A shortcut: modifiers plus a key name. Keys are lowercase letters, digits,
/// "left" "right" "up" "down", "space", punctuation, or other key names
/// ("tab", "f5"), as in the Hammerspoon version.
public struct Combo: Codable, Hashable {
    public var mods: Set<Mod>
    public var key: String

    public init(mods: Set<Mod>, key: String) {
        self.mods = mods
        self.key = key
    }

    public init(_ key: String, _ mods: Mod...) {
        self.init(mods: Set(mods), key: key)
    }

    /// Stable identity: "ctrl+alt+cmd+shift|g".
    public var id: String {
        Mod.allCases.filter { mods.contains($0) }.map(\.rawValue).joined(separator: "+") + "|" + key
    }

    /// "⌃⌥⌘G⇧"
    public var formatted: String {
        formatMods(mods) + keyLabel(key) + (mods.contains(.shift) ? Mod.shift.symbol : "")
    }

    public func plus(_ extra: Mod...) -> Combo {
        Combo(mods: mods.union(extra), key: key)
    }

    /// Reads what `formatted` writes: leading modifier symbols in any order,
    /// an optional trailing ⇧, then the key label.
    public static func parse(_ s: String) -> Combo? {
        var mods = Set<Mod>()
        var rest = Substring(s)
        var changed = true
        while changed {
            changed = false
            for m in Mod.allCases where rest.hasPrefix(m.symbol) {
                mods.insert(m)
                rest = rest.dropFirst(m.symbol.count)
                changed = true
            }
        }
        if rest.hasSuffix(Mod.shift.symbol) && rest.count > Mod.shift.symbol.count {
            mods.insert(.shift)
            rest = rest.dropLast(Mod.shift.symbol.count)
        }
        if rest.isEmpty { return nil }
        let label = String(rest)
        return Combo(mods: mods, key: labelKeys[label] ?? label.lowercased())
    }
}

private let keyLabels = ["left": "←", "right": "→", "up": "↑", "down": "↓", "space": "Space"]
private let labelKeys = Dictionary(uniqueKeysWithValues: keyLabels.map { ($1, $0) })

/// "⌃⌥⌘" (never ⇧: it goes after the key).
public func formatMods(_ mods: Set<Mod>) -> String {
    [Mod.ctrl, .alt, .cmd].filter { mods.contains($0) }.map(\.symbol).joined()
}

/// How a key is shown: arrows as ←→↑↓, "Space", letters upper-case, other
/// names capitalized ("f12" → "F12").
public func keyLabel(_ key: String) -> String {
    if let l = keyLabels[key] { return l }
    if key.count == 1 { return key.uppercased() }
    return key.prefix(1).uppercased() + key.dropFirst()
}
