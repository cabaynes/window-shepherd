import Foundation

public enum Owner: Hashable {
    case action(ActionID), screen, menu
}

public enum Scope: String {
    case window, app, all
}

/// One shortcut the config produces. `entries` are the config settings it
/// depends on (what to blame, or reset, when it clashes).
public struct ShortcutBinding: Equatable {
    public let combo: Combo
    public let owner: Owner
    public let scope: Scope
    public let nextScreen: Bool
    public let screen: Int?
    public let label: String
    public let base: Bool
    public let entries: [Entry]
}

public struct Problem: Equatable {
    public let combo: Combo?
    public let owners: [String]
    public let why: String
    public let entries: [Entry]
}

/// Every shortcut the config produces, in the Hammerspoon version's order:
/// per action its base, + whole app, + next screen, + both (a modifier
/// already in the base isn't added); screens 1–9 × this window / whole app /
/// everything; then the menu key.
public func derive(_ cfg: ShortcutConfig) -> [ShortcutBinding] {
    var out: [ShortcutBinding] = []
    let W = cfg.wholeApp, N = cfg.nextScreen
    for a in ActionID.allCases {
        guard let b = cfg.actions[a] else { continue }
        let e = Entry.action(a)
        let hasW = b.mods.contains(W), hasN = b.mods.contains(N)
        out.append(ShortcutBinding(combo: b, owner: .action(a), scope: .window, nextScreen: false, screen: nil,
                                   label: a.rawValue, base: true, entries: [e]))
        if !hasW {
            out.append(ShortcutBinding(combo: b.plus(W), owner: .action(a), scope: .app, nextScreen: false, screen: nil,
                                       label: a.rawValue + " (whole app)", base: false, entries: [e, .wholeApp]))
        }
        if !hasN {
            out.append(ShortcutBinding(combo: b.plus(N), owner: .action(a), scope: .window, nextScreen: true, screen: nil,
                                       label: a.rawValue + " (next screen)", base: false, entries: [e, .nextScreen]))
        }
        if !hasW && !hasN {
            out.append(ShortcutBinding(combo: b.plus(W, N), owner: .action(a), scope: .app, nextScreen: true, screen: nil,
                                       label: a.rawValue + " (whole app, next screen)", base: false,
                                       entries: [e, .wholeApp, .nextScreen]))
        }
    }
    for n in 1...9 {
        let b = Combo(mods: cfg.screenBase, key: String(n))
        out.append(ShortcutBinding(combo: b, owner: .screen, scope: .window, nextScreen: false, screen: n,
                                   label: "Screen \(n) (this window)", base: true, entries: [.screenBase]))
        out.append(ShortcutBinding(combo: b.plus(W), owner: .screen, scope: .app, nextScreen: false, screen: n,
                                   label: "Screen \(n) (whole app)", base: false, entries: [.screenBase, .wholeApp]))
        out.append(ShortcutBinding(combo: b.plus(W, N), owner: .screen, scope: .all, nextScreen: false, screen: n,
                                   label: "Screen \(n) (everything)", base: false,
                                   entries: [.screenBase, .wholeApp, .nextScreen]))
    }
    out.append(ShortcutBinding(combo: cfg.menu, owner: .menu, scope: .window, nextScreen: false, screen: nil,
                               label: "Open the menu", base: true, entries: [.menu]))
    return out
}

/// App and window switching: macOS doesn't always report these as its own,
/// and losing them would be far worse than any clash warning.
private let reserved: Set<String> = ["cmd|tab", "cmd+shift|tab", "cmd|`", "cmd+shift|`"]

/// Everything wrong with a config; empty means it's safe to bind.
public func validate(_ cfg: ShortcutConfig) -> [Problem] {
    var problems: [Problem] = []
    let W = cfg.wholeApp, N = cfg.nextScreen
    if W == N {
        problems.append(Problem(combo: nil, owners: ["Whole app", "Next screen"],
                                why: "“Whole app” and “Next screen” must be different modifier keys",
                                entries: [.wholeApp, .nextScreen]))
    }
    if cfg.screenBase.contains(W) || cfg.screenBase.contains(N) {
        problems.append(Problem(combo: nil, owners: ["Screens"],
                                why: "The screen keys can't include the “whole app” or “next screen” modifier",
                                entries: [.screenBase, .wholeApp, .nextScreen]))
    }
    var byId: [String: [ShortcutBinding]] = [:]
    var order: [String] = []
    for b in derive(cfg) {
        let m = b.combo.mods
        if reserved.contains(b.combo.id) {
            problems.append(Problem(combo: b.combo, owners: [b.label],
                                    why: b.combo.formatted + " switches apps and windows, so it can't be a Window Shepherd shortcut",
                                    entries: b.entries))
        }
        if b.base && !(m.contains(.ctrl) || m.contains(.alt) || m.contains(.cmd)) {
            problems.append(Problem(combo: b.combo, owners: [b.label],
                                    why: "A shortcut needs ⌃, ⌥ or ⌘, so it doesn't get in the way of typing",
                                    entries: b.entries))
        }
        if byId[b.combo.id] == nil { order.append(b.combo.id) }
        byId[b.combo.id, default: []].append(b)
    }
    for id in order {
        let list = byId[id]!
        guard list.count > 1 else { continue }
        let owners = list.map(\.label)
        problems.append(Problem(combo: list[0].combo, owners: owners,
                                why: list[0].combo.formatted + " is used twice: " + owners.joined(separator: " and "),
                                entries: list.flatMap(\.entries)))
    }
    return problems
}

public extension Array where Element == ShortcutBinding {
    func find(_ owner: Owner, _ scope: Scope, next: Bool = false, screen: Int? = nil) -> ShortcutBinding? {
        first { $0.owner == owner && $0.scope == scope && $0.nextScreen == next && $0.screen == screen }
    }
}
