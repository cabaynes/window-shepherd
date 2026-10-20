import CoreGraphics

/// The ⧉ menu as data, built only from the fast window list, so opening it
/// is instant. The app renders it; tests read it.
public indirect enum MenuNode: Equatable {
    case item(title: String, keys: String?, action: MenuAction, indent: Int = 0)
    case header(String)                          // bold, enabled, does nothing
    case reference(keys: String, what: String)   // a shortcut list row: keys first, full-strength text
    case submenu(title: String, keys: String?, children: [MenuNode])
    case toggle(title: String, on: Bool, action: MenuAction)
    case separator
}

public enum MenuAction: Equatable {
    case apply(Selection, Placer, label: String)
    /// Re-checked at click time: the menu may have been open across an unplug.
    case moveTo(uuid: String, name: String, Placer, Selection, label: String)
    case retry, customize, noop, launchAtLogin, about, checkForUpdates, quit, grantAccess
}

public struct MenuInputs {
    public var ctx: MenuContext
    public var screens: [ScreenInfo]
    public var bindings: [ShortcutBinding]
    public var config: ShortcutConfig
    public var retry: (count: Int, titles: [String])?
    public var launchAtLogin: Bool
    public var needsAccess = false

    public init(ctx: MenuContext, screens: [ScreenInfo], bindings: [ShortcutBinding], config: ShortcutConfig,
                retry: (count: Int, titles: [String])?, launchAtLogin: Bool, needsAccess: Bool = false) {
        self.ctx = ctx; self.screens = screens; self.bindings = bindings; self.config = config
        self.retry = retry; self.launchAtLogin = launchAtLogin; self.needsAccess = needsAccess
    }
}

public enum MenuModel {
    public enum Resolved: Equatable {
        case run(Selection, Placer, label: String)
        case refused(String)
    }

    /// What a clicked action does now: a "Move to" whose screen is gone is refused.
    public static func resolve(_ a: MenuAction, screens: [ScreenInfo]) -> Resolved? {
        switch a {
        case let .apply(sel, placer, label): return .run(sel, placer, label: label)
        case let .moveTo(uuid, name, placer, sel, label):
            guard screens.contains(where: { $0.uuid == uuid }) else { return .refused(name + " isn't connected anymore") }
            return .run(sel, placer, label: label)
        default: return nil
        }
    }

    /// Action first, then who: the actions, "Move to <screen>", then settings
    /// and the app's own items. The retry offer, when there is one, goes on top.
    public static func build(_ i: MenuInputs) -> [MenuNode] {
        var menu: [MenuNode] = []
        if i.needsAccess {
            menu += [.item(title: "Grant Accessibility permission…", keys: nil, action: .grantAccess), .separator]
        }
        if let r = i.retry {
            menu.append(.item(title: "Retry \(r.count) window\(r.count == 1 ? "" : "s") that didn't move", keys: nil, action: .retry))
            for (n, t) in r.titles.enumerated() {
                if n == 8 {
                    menu.append(.item(title: "and \(r.titles.count - 8) more", keys: nil, action: .retry, indent: 1))
                    break
                }
                menu.append(.item(title: t, keys: nil, action: .retry, indent: 1))
            }
            menu.append(.separator)
        }
        func key(_ o: Owner, _ s: Scope, next: Bool = false, screen: Int? = nil) -> String? {
            i.bindings.find(o, s, next: next, screen: screen)?.combo.formatted
        }
        for a in ActionID.allCases {
            if a == .leftHalf || a == .topLeft { menu.append(.separator) }
            let keys = [key(.action(a), .window), key(.action(a), .app)]
            let placer = Placer(a.placement, on: .own)
            menu.append(.submenu(title: a.rawValue, keys: keys[0],
                                 children: scopeMenu(i.ctx, keys) { .apply($0, placer, label: a.rawValue) }))
        }
        menu.append(.separator)

        // "Move to" lists only the screens the front window isn't on (all of them if there's none).
        let here = i.ctx.frontFrame.flatMap { Geometry.screen(mostOf: $0, in: i.screens) }?.uuid
        let dests = Screens.destinations(i.screens)
        if dests.count >= 2 {
            let sizes: [(String, ActionID, Placer.Kind)] = [("Full screen", .fullScreen, .fraction(1)),
                                                             ("90%", .almost, .fraction(0.9)),
                                                             ("same size", .center, .center)]
            for d in dests where d.screen.uuid != here {
                let dname = "\(d.name) (\(d.num))"
                for (size, action, kind) in sizes {
                    let label = "\(dname) (\(size))"
                    let placer = kind.placer(on: .fixed(uuid: d.screen.uuid))
                    // Which hotkeys do this exact move: this window, this app, everything.
                    // With two screens, the ⇧ (next screen) keys land on this one.
                    var keys: [String?] = []
                    if dests.count == 2 { keys = [key(.action(action), .window, next: true), key(.action(action), .app, next: true)] }
                    if (d.isLaptop && size == "Full screen") || (!d.isLaptop && size == "90%") {
                        keys = [key(.screen, .window, screen: d.num), key(.screen, .app, screen: d.num), key(.screen, .all, screen: d.num)]
                    }
                    menu.append(.submenu(title: "Move to \(dname) — \(size)", keys: keys.first ?? nil,
                                         children: scopeMenu(i.ctx, keys) {
                                             .moveTo(uuid: d.screen.uuid, name: dname, placer, $0, label: label)
                                         }))
                }
            }
            menu.append(.separator)
        }
        menu.append(.item(title: "Customize shortcuts…", keys: nil, action: .customize))
        menu.append(.submenu(title: "Keyboard shortcuts", keys: nil, children: shortcutReference(i.config, i.bindings)))
        menu.append(.separator)
        menu.append(.toggle(title: "Launch at Login", on: i.launchAtLogin, action: .launchAtLogin))
        menu.append(.item(title: "About Window Shepherd", keys: nil, action: .about))
        menu.append(.item(title: "Check for Updates…", keys: nil, action: .checkForUpdates))
        menu.append(.separator)
        menu.append(.item(title: "Quit Window Shepherd", keys: nil, action: .quit))
        return menu
    }

    /// The "who" submenu under every action.
    static func scopeMenu(_ ctx: MenuContext, _ keys: [String?], _ act: (Selection) -> MenuAction) -> [MenuNode] {
        func k(_ n: Int) -> String? { n < keys.count ? keys[n] : nil }
        var items: [MenuNode] = []
        if let f = ctx.front {
            items.append(.item(title: "This window (\(f.name))", keys: k(0), action: act(Selection(pid: f.pid, winId: ctx.frontWin))))
            items.append(.item(title: "All \(f.name) windows (\(f.count))", keys: k(1), action: act(Selection(pid: f.pid))))
            items.append(.separator)
        }
        items.append(.item(title: "Everything (\(ctx.total) windows)", keys: k(2), action: act(.everything)))
        if !ctx.others.isEmpty { items.append(.separator) }
        for a in ctx.others {
            items.append(.item(title: "\(a.name) (\(a.count))", keys: nil, action: act(Selection(pid: a.pid))))
        }
        return items
    }

    /// The "Keyboard shortcuts" reference list, with the user's own keys.
    public static func shortcutReference(_ cfg: ShortcutConfig, _ bindings: [ShortcutBinding]) -> [MenuNode] {
        func label(_ o: Owner, _ s: Scope, next: Bool = false, screen: Int? = nil) -> String? {
            bindings.find(o, s, next: next, screen: screen)?.combo.formatted
        }
        func combo(_ a: ActionID) -> Combo { cfg.actions[a] ?? ShortcutConfig.defaults.actions[a]! }
        // One row for a group when they share modifiers and their keys are the arrows.
        func groupRows(_ ids: [ActionID], _ what: String) -> [MenuNode] {
            let first = combo(ids[0])
            let arrows: Set<String> = ["left", "right", "up", "down"]
            let same = ids.allSatisfy {
                let c = combo($0)
                return formatMods(c.mods) == formatMods(first.mods) && c.mods.contains(.shift) == first.mods.contains(.shift)
                    && arrows.contains(c.key)
            }
            if same {
                let keys = ids.map { keyLabel(combo($0).key) }.joined(separator: " ")
                return [.reference(keys: formatMods(first.mods) + " " + keys + (first.mods.contains(.shift) ? " ⇧" : ""), what: what)]
            }
            return ids.map { .reference(keys: combo($0).formatted, what: $0.rawValue) }
        }
        let W = cfg.wholeApp, N = cfg.nextScreen
        var list: [MenuNode] = [.header("THIS WINDOW")]
        list += groupRows([.leftHalf, .rightHalf, .topHalf, .bottomHalf], "Left / right / top / bottom half")
        for a in [ActionID.fullScreen, .almost, .sixty, .center] { list.append(.reference(keys: combo(a).formatted, what: a.rawValue)) }
        list += groupRows([.topLeft, .topRight, .bottomLeft, .bottomRight], "Top left / top right / bottom left / bottom right")
        list += [.separator, .header("ADD A KEY")]
        let noApp = ActionID.allCases.filter { label(.action($0), .app) == nil }
        let cornersOnly = noApp == [.topLeft, .topRight, .bottomLeft, .bottomRight]
        list.append(.reference(keys: "+ " + W.symbol, what: "Every window of the app" +
            (cornersOnly ? "   (not corners: use the menu)" : (noApp.isEmpty ? "" : "   (some: use the menu)"))))
        let centerNext = label(.action(.center), .window, next: true)
        list.append(.reference(keys: "+ " + N.symbol, what: "On the next screen" +
            (centerNext.map { "   (\($0) = this window to the next screen, same size)" } ?? "")))
        let both: Set<Mod> = [W, N]
        list.append(.reference(keys: "+ " + formatMods(both) + (both.contains(.shift) ? "⇧" : ""),
                               what: "Every window of the app, on the next screen"))
        list += [.separator, .header("SCREENS   (1 = laptop, then monitors left to right)")]
        func screenKeys(_ s: Scope) -> String {
            let c = bindings.find(.screen, s, screen: 1)?.combo ?? Combo(mods: cfg.screenBase, key: "1")
            return formatMods(c.mods) + " 1 2 3" + (c.mods.contains(.shift) ? " ⇧" : "")
        }
        list.append(.reference(keys: screenKeys(.window), what: "This window → that screen (laptop full screen, monitors 90%)"))
        list.append(.reference(keys: screenKeys(.app), what: "Every window of the app → that screen"))
        list.append(.reference(keys: screenKeys(.all), what: "EVERYTHING → that screen"))
        list += [.separator, .header("MENU")]
        list.append(.reference(keys: cfg.menu.formatted, what: "Open this menu under the mouse"))
        return list
    }
}

extension Placer {
    enum Kind { case fraction(Double), center
        func placer(on t: TargetScreen) -> Placer {
            switch self {
            case .fraction(let f): return .fraction(f, on: t)
            case .center: return .center(t)
            }
        }
    }
}
