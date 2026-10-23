import Foundation

/// The window actions, in menu order. The raw value is the user-visible name
/// (and the id the Hammerspoon version used).
public enum ActionID: String, CaseIterable, Codable {
    case fullScreen = "Full screen", almost = "90%", sixty = "60%", center = "Center (keep size)"
    case leftHalf = "Left half", rightHalf = "Right half", topHalf = "Top half", bottomHalf = "Bottom half"
    case topLeft = "Top left", topRight = "Top right", bottomLeft = "Bottom left", bottomRight = "Bottom right"

    public var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return true
        default: return false
        }
    }
}

/// One setting in the shortcut config — what a clash can be blamed on and reset.
public enum Entry: Hashable {
    case action(ActionID), wholeApp, nextScreen, screenBase, menu

    public var name: String {
        switch self {
        case .action(let a): return a.rawValue
        case .wholeApp: return "Whole app"
        case .nextScreen: return "Next screen"
        case .screenBase: return "Screens"
        case .menu: return "Open the menu"
        }
    }

    /// The Hammerspoon version's entry string ("action:90%", "wholeApp", …).
    public var key: String {
        switch self {
        case .action(let a): return "action:" + a.rawValue
        case .wholeApp: return "wholeApp"
        case .nextScreen: return "nextScreen"
        case .screenBase: return "screenBase"
        case .menu: return "menu"
        }
    }
}

public enum EntryValue: Equatable {
    case combo(Combo), mod(Mod), mods(Set<Mod>)
}

/// The user's shortcuts: one base combo per action, the two "add a key"
/// modifiers, the screen-number base and the menu key. Everything else is
/// derived from these (see `derive`).
public struct ShortcutConfig: Equatable {
    public var actions: [ActionID: Combo]
    public var wholeApp: Mod
    public var nextScreen: Mod
    public var screenBase: Set<Mod>
    public var menu: Combo

    public init(actions: [ActionID: Combo], wholeApp: Mod, nextScreen: Mod, screenBase: Set<Mod>, menu: Combo) {
        self.actions = actions
        self.wholeApp = wholeApp
        self.nextScreen = nextScreen
        self.screenBase = screenBase
        self.menu = menu
    }

    /// Charles's scheme (2026-10-19): ⌥⌘ + key = this window; corners on ⌃⌘
    /// arrows (his old Rectangle layout, with ← and ↓ swapped 2026-10-23 so the
    /// corners go round clockwise: ↑ top left, → top right, ↓ bottom right, ← bottom left); ⌃ = whole app; ⇧ = next screen.
    public static var defaults: ShortcutConfig {
        ShortcutConfig(
            actions: [
                .fullScreen: Combo("f", .alt, .cmd), .almost: Combo("g", .alt, .cmd),
                .sixty: Combo("h", .alt, .cmd), .center: Combo("c", .alt, .cmd),
                .leftHalf: Combo("left", .alt, .cmd), .rightHalf: Combo("right", .alt, .cmd),
                .topHalf: Combo("up", .alt, .cmd), .bottomHalf: Combo("down", .alt, .cmd),
                .topLeft: Combo("up", .ctrl, .cmd), .topRight: Combo("right", .ctrl, .cmd),
                .bottomLeft: Combo("left", .ctrl, .cmd), .bottomRight: Combo("down", .ctrl, .cmd),
            ],
            wholeApp: .ctrl, nextScreen: .shift, screenBase: [.alt, .cmd],
            menu: Combo("m", .ctrl, .alt, .cmd))
    }

    /// True when this binds exactly the defaults (so nothing needs saving).
    public var isDefault: Bool {
        let d = ShortcutConfig.defaults
        return wholeApp == d.wholeApp && nextScreen == d.nextScreen && screenBase == d.screenBase
            && menu.id == d.menu.id
            && ActionID.allCases.allSatisfy { actions[$0]?.id == d.actions[$0]?.id }
    }

    public subscript(entry: Entry) -> EntryValue {
        get {
            switch entry {
            case .action(let a): return .combo(actions[a] ?? ShortcutConfig.defaults.actions[a]!)
            case .wholeApp: return .mod(wholeApp)
            case .nextScreen: return .mod(nextScreen)
            case .screenBase: return .mods(screenBase)
            case .menu: return .combo(menu)
            }
        }
        set {
            switch (entry, newValue) {
            case (.action(let a), .combo(let c)): actions[a] = c
            case (.wholeApp, .mod(let m)): wholeApp = m
            case (.nextScreen, .mod(let m)): nextScreen = m
            case (.screenBase, .mods(let m)): screenBase = m
            case (.menu, .combo(let c)): menu = c
            default: assertionFailure("\(entry) can't hold \(newValue)")
            }
        }
    }
}

// JSON: {"actions":{"90%":{"mods":["alt","cmd"],"key":"g"}},"wholeApp":"ctrl",
//        "nextScreen":"shift","screenBase":["alt","cmd"],"menu":{…}}
extension Combo {
    private enum CodingKeys: String, CodingKey { case mods, key }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mods = Set(try c.decode([Mod].self, forKey: .mods))
        key = try c.decode(String.self, forKey: .key)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mods.sorted(), forKey: .mods)
        try c.encode(key, forKey: .key)
    }
}

extension ShortcutConfig: Codable {
    private enum CodingKeys: String, CodingKey { case actions, wholeApp, nextScreen, screenBase, menu }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode([String: Combo].self, forKey: .actions)
        var actions: [ActionID: Combo] = [:]
        for (k, v) in raw { if let a = ActionID(rawValue: k) { actions[a] = v } }
        self.init(actions: actions,
                  wholeApp: try c.decode(Mod.self, forKey: .wholeApp),
                  nextScreen: try c.decode(Mod.self, forKey: .nextScreen),
                  screenBase: Set(try c.decode([Mod].self, forKey: .screenBase)),
                  menu: try c.decode(Combo.self, forKey: .menu))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Dictionary(uniqueKeysWithValues: actions.map { ($0.rawValue, $1) }), forKey: .actions)
        try c.encode(wholeApp, forKey: .wholeApp)
        try c.encode(nextScreen, forKey: .nextScreen)
        try c.encode(screenBase.sorted(), forKey: .screenBase)
        try c.encode(menu, forKey: .menu)
    }
}
