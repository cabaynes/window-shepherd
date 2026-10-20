import Foundation

/// A shortcut macOS owns (it takes the key before any app sees it).
public struct SystemShortcut: Equatable {
    public let combo: Combo
    public let name: String
    public init(combo: Combo, name: String) { self.combo = combo; self.name = name }
}

/// A shortcut an app uses (from its menus, a custom app shortcut, or the built-in list).
public struct AppShortcut: Equatable {
    public let combo: Combo
    public let app: String
    public let what: String
    public init(combo: Combo, app: String, what: String) { self.combo = combo; self.app = app; self.what = what }
}

public struct ClashSources: Equatable {
    public var system: [SystemShortcut]
    public var apps: [AppShortcut]
    public init(system: [SystemShortcut] = [], apps: [AppShortcut] = []) { self.system = system; self.apps = apps }
}

public struct Finding: Equatable {
    public enum Level: Equatable { case block, warn }
    public let level: Level
    public let source: String
    public let text: String
}

/// Turns the ways macOS and apps describe shortcuts into combos, and compares
/// them with Window Shepherd's own.
public enum Conflicts {
    private static let glyphKeys = [100: "left", 101: "right", 104: "up", 106: "down", 9: "space"]

    /// An app menu item's shortcut as Accessibility reports it: AXMenuItemCmdChar,
    /// AXMenuItemCmdModifiers (bit 8 set = no ⌘; 1 = ⇧, 2 = ⌥, 4 = ⌃) and
    /// AXMenuItemCmdGlyph (arrows, Space). nil if the item has no shortcut.
    public static func fromAXMenu(cmdChar: String?, modifiers: Int?, glyph: Int?) -> Combo? {
        var key = glyph.flatMap { glyphKeys[$0] }
        if key == nil {
            guard let c = cmdChar, !c.isEmpty else { return nil }
            key = c.lowercased()
        }
        let m = modifiers ?? 0
        var mods = Set<Mod>()
        if m & 8 == 0 { mods.insert(.cmd) }
        if m & 1 != 0 { mods.insert(.shift) }
        if m & 2 != 0 { mods.insert(.alt) }
        if m & 4 != 0 { mods.insert(.ctrl) }
        return Combo(mods: mods, key: key!)
    }

    private static let ukeMods: [Character: Mod] = ["@": .cmd, "~": .alt, "^": .ctrl, "$": .shift]
    private static let ukeKeys = ["\u{2190}": "left", "\u{2192}": "right", "\u{2191}": "up", "\u{2193}": "down"]

    /// A custom app shortcut from System Settings (NSUserKeyEquivalents), e.g. "@~g".
    public static func fromUserKeyEquivalent(_ s: String?) -> Combo? {
        guard let s else { return nil }
        var mods = Set<Mod>()
        var rest = Substring(s)
        while let c = rest.first, let m = ukeMods[c] {
            mods.insert(m)
            rest = rest.dropFirst()
        }
        guard !rest.isEmpty else { return nil }
        return Combo(mods: mods, key: ukeKeys[String(rest)] ?? rest.lowercased())
    }

    /// A macOS system shortcut: key name plus NSEvent modifier flags
    /// (⇧ 1<<17, ⌃ 1<<18, ⌥ 1<<19, ⌘ 1<<20).
    public static func fromSymbolic(keyName: String?, flags: Int) -> Combo? {
        guard let keyName, !keyName.isEmpty else { return nil }
        var mods = Set<Mod>()
        if flags & (1 << 17) != 0 { mods.insert(.shift) }
        if flags & (1 << 18) != 0 { mods.insert(.ctrl) }
        if flags & (1 << 19) != 0 { mods.insert(.alt) }
        if flags & (1 << 20) != 0 { mods.insert(.cmd) }
        return Combo(mods: mods, key: keyName)
    }

    /// Findings for the combos Window Shepherd binds, keyed by `Combo.id`:
    /// macOS shortcuts block (they'd never work), app shortcuts warn. One
    /// finding per source per combo; blocks first.
    public static func check(bindings: [Combo], sources: ClashSources) -> [String: [Finding]] {
        let bound = Set(bindings.map(\.id))
        var found: [String: [Finding]] = [:]
        var seen = Set<String>()
        func add(_ combo: Combo, _ level: Finding.Level, _ source: String, _ text: String) {
            let id = combo.id
            guard bound.contains(id), seen.insert(id + "\0" + source).inserted else { return }
            found[id, default: []].append(Finding(level: level, source: source, text: text))
        }
        for e in sources.system {
            add(e.combo, .block, "macOS: " + e.name, "macOS takes this first, so it would never work: " + e.name)
        }
        for e in sources.apps {
            add(e.combo, .warn, e.app, e.app + ": " + e.what + ". Yours will win.")
        }
        for (id, list) in found {
            found[id] = list.filter { $0.level == .block } + list.filter { $0.level == .warn }
        }
        return found
    }
}
