import Foundation

/// A derived shortcut shown beside a box ("⌃⌥⌘G whole app"); keys nil = menu only.
public struct ChipVM: Equatable {
    public let label: String
    public let keys: String?
    public let level: Finding.Level?
    public let text: String?
}

/// One row of the Customize Shortcuts window.
public struct RowVM: Equatable {
    public let entry: Entry
    public let name: String
    public let section: String
    public let keys: String
    public let level: Finding.Level?
    public let text: String?
    public let isDefault: Bool
    public let chips: [ChipVM]
}

public struct SettingsVM: Equatable {
    public let rows: [RowVM]
    public let menu: RowVM
    public let wholeApp: Mod
    public let nextScreen: Mod
    public let screenBase: Set<Mod>
    public let screenChips: [ChipVM]
}

/// What the Customize Shortcuts window shows for `config`, with every clash
/// the sources know about.
public func settingsVM(config: ShortcutConfig, sources: ClashSources,
                       systemCheck: ([Combo]) -> [SystemShortcut]) -> SettingsVM {
    let (found, bindings) = findings(for: config, sources: sources, systemCheck: systemCheck)
    let defaults = ShortcutConfig.defaults
    func chip(_ owner: Owner, _ scope: Scope, next: Bool = false, screen: Int? = nil, _ label: String) -> ChipVM {
        guard let b = bindings.find(owner, scope, next: next, screen: screen) else {
            return ChipVM(label: label, keys: nil, level: nil, text: nil)
        }
        let f = found[b.combo.id]?.first
        return ChipVM(label: label, keys: b.combo.formatted, level: f?.level, text: f?.text)
    }
    let rows = ActionID.allCases.map { a -> RowVM in
        let base = config.actions[a] ?? defaults.actions[a]!
        let f = found[base.id]?.first
        return RowVM(entry: .action(a), name: a.rawValue, section: a.isCorner ? "Corners" : "This window",
                     keys: base.formatted, level: f?.level, text: f?.text, isDefault: base.id == defaults.actions[a]!.id,
                     chips: [chip(.action(a), .app, "whole app"), chip(.action(a), .window, next: true, "next screen"),
                             chip(.action(a), .app, next: true, "both")])
    }
    let mf = found[config.menu.id]?.first
    let menu = RowVM(entry: .menu, name: "Open the menu under the mouse", section: "Menu", keys: config.menu.formatted,
                     level: mf?.level, text: mf?.text, isDefault: config.menu.id == defaults.menu.id, chips: [])
    let screenChips = [chip(.screen, .window, screen: 1, "this window"), chip(.screen, .app, screen: 1, "whole app"),
                       chip(.screen, .all, screen: 1, "everything")].map { c in
        ChipVM(label: c.label, keys: c.keys.map { $0.replacingOccurrences(of: "1", with: "n") }, level: c.level, text: c.text)
    }
    return SettingsVM(rows: rows, menu: menu, wholeApp: config.wholeApp, nextScreen: config.nextScreen,
                      screenBase: config.screenBase, screenChips: screenChips)
}
