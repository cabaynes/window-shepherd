import Foundation

/// A derived shortcut listed beside a box ("Every window of the app  ⌃⌥⌘G"); keys nil = menu only.
public struct ChipVM: Equatable {
    public let label: String
    public let keys: String?
    public let level: Finding.Level?
    public let text: String?

    public init(label: String, keys: String?, level: Finding.Level?, text: String?) {
        self.label = label; self.keys = keys; self.level = level; self.text = text
    }
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
    /// The three screen keys for each screen number: [0] is screen 1, up to 9.
    public let screenKeys: [[ChipVM]]
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
                     chips: [chip(.action(a), .app, "Every window of the app"), chip(.action(a), .window, next: true, "On the next screen"),
                             chip(.action(a), .app, next: true, "Both")])
    }
    let mf = found[config.menu.id]?.first
    let menu = RowVM(entry: .menu, name: "Open the menu under the mouse", section: "Menu", keys: config.menu.formatted,
                     level: mf?.level, text: mf?.text, isDefault: config.menu.id == defaults.menu.id, chips: [])
    let screenKeys = (1...9).map { n in
        [chip(.screen, .window, screen: n, "This window"), chip(.screen, .app, screen: n, "Every window of the app"),
         chip(.screen, .all, screen: n, "Every window of every app")]
    }
    return SettingsVM(rows: rows, menu: menu, wholeApp: config.wholeApp, nextScreen: config.nextScreen,
                      screenBase: config.screenBase, screenKeys: screenKeys)
}
