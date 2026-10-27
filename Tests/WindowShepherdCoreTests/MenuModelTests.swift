import XCTest
@testable import WindowShepherdCore

final class MenuModelTests: XCTestCase {
    let lap = screen(1, "Built-in", x: 0, builtin: true)
    let dell = screen(2, "DELL", x: 1000)

    func inputs(screens: [ScreenInfo]? = nil, frontX: CGFloat = 100, retry: (Int, [String])? = nil,
                cfg: ShortcutConfig = .defaults) -> MenuInputs {
        var ctx = MenuContext()
        ctx.front = .init(pid: 10, name: "Safari", count: 3)
        ctx.frontWin = 1
        ctx.frontFrame = CGRect(x: frontX, y: 125, width: 400, height: 300)
        ctx.total = 5
        ctx.others = [.init(pid: 11, name: "Mail", count: 2)]
        return MenuInputs(ctx: ctx, screens: screens ?? [lap, dell], bindings: derive(cfg), config: cfg,
                          retry: retry.map { (count: $0.0, titles: $0.1) }, launchAtLogin: true)
    }

    func testRevertRowsOnTop() {
        var i = inputs(retry: (1, ["Safari — Doc"]))
        let at = Date()
        i.revert = RevertInfo(label: "Built-in + DELL", at: at, notWhere: 32)
        let m = MenuModel.build(i)
        XCTAssertEqual(m[0], .item(title: "Revert Built-in + DELL", keys: nil, action: .revert))
        XCTAssertEqual(m[1], .item(title: "to how it was at \(MenuModel.revertTime(at, now: at)), before they were separated",
                                   keys: nil, action: .revert, indent: 1))
        XCTAssertEqual(m[2], .item(title: "32 windows aren't where they were then", keys: nil, action: .revert, indent: 1))
        XCTAssertEqual(m[3], .separator)
        XCTAssertEqual(titles(m)[4], "Retry 1 window that didn't move")
    }

    func testRevertCountWording() {
        var i = inputs()
        i.revert = RevertInfo(label: "A + B", at: Date(), notWhere: 1)
        XCTAssertEqual(titles(MenuModel.build(i))[2], "1 window isn't where it was then")
        i.revert = RevertInfo(label: "A + B", at: Date(), notWhere: 0)
        XCTAssertEqual(titles(MenuModel.build(i))[2], "Every window is where it was then")
    }

    func testNoRevertRowWithoutFrozenCopy() {
        XCTAssertFalse(titles(MenuModel.build(inputs())).contains { $0.hasPrefix("Revert") })
    }

    func testRevertTimeShowsTheDayWhenNotToday() {
        let now = Date()
        let yesterday = now.addingTimeInterval(-86400)
        XCTAssertNotEqual(MenuModel.revertTime(yesterday, now: now), MenuModel.revertTime(now, now: now))
        XCTAssertFalse(MenuModel.revertTime(now, now: now).isEmpty)
    }

    func titles(_ nodes: [MenuNode]) -> [String] {
        nodes.map {
            switch $0 {
            case .item(let t, _, _, _), .submenu(let t, _, _), .toggle(let t, _, _): return t
            case .header(let t): return "#" + t
            case .reference(let k, let w): return k + " | " + w
            case .separator: return "-"
            }
        }
    }

    func submenu(_ nodes: [MenuNode], _ title: String) -> (keys: String?, children: [MenuNode])? {
        for n in nodes { if case let .submenu(t, k, c) = n, t == title { return (k, c) } }
        return nil
    }

    func testActionsThenScopes() {
        let menu = MenuModel.build(inputs())
        guard case let .submenu(title, keys, children) = menu[0] else { return XCTFail("first is a submenu") }
        XCTAssertEqual(title, "Full screen")
        XCTAssertEqual(keys, "⌥⌘F")
        XCTAssertEqual(titles(children), ["This window (Safari)", "All Safari windows (3)", "-", "Everything (5 windows)", "-", "Mail (2)"])
        guard case let .item(_, k0, a0, _) = children[0], case let .item(_, k1, a1, _) = children[1] else { return XCTFail() }
        XCTAssertEqual(k0, "⌥⌘F")
        XCTAssertEqual(k1, "⌃⌥⌘F")
        XCTAssertEqual(a0, .apply(Selection(pid: 10, winId: 1), .unit(UnitRect(x: 0, y: 0, w: 1, h: 1), .own), label: "Full screen"))
        XCTAssertEqual(a1, .apply(Selection(pid: 10), .unit(UnitRect(x: 0, y: 0, w: 1, h: 1), .own), label: "Full screen"))
        XCTAssertEqual(Array(titles(menu).prefix(15)), ["Full screen", "90%", "60%", "Center (keep size)", "-",
            "Left half", "Right half", "Top half", "Bottom half", "-", "Top left", "Top right", "Bottom left", "Bottom right", "-"])
        guard case let .item(allTitle, allKeys, _, _) = submenu(menu, "Top left")!.children[1] else { return XCTFail() }
        XCTAssertEqual(allTitle, "All Safari windows (3)")
        XCTAssertNil(allKeys, "no whole-app corner key")
    }

    func testBottomOfMenu() {
        let t = titles(MenuModel.build(inputs()))
        XCTAssertEqual(Array(t.suffix(9)), ["-", "Customize shortcuts…", "Keyboard shortcuts", "-",
            "Launch at Login", "About Window Shepherd", "Check for Updates…", "-", "Quit Window Shepherd"])
    }

    func testMoveToHidesCurrentScreenAndSingleScreen() {
        let onLaptop = titles(MenuModel.build(inputs()))
        XCTAssertTrue(onLaptop.contains("Move to DELL (2) — Full screen"))
        XCTAssertTrue(onLaptop.contains("Move to DELL (2) — 90%"))
        XCTAssertTrue(onLaptop.contains("Move to DELL (2) — same size"))
        XCTAssertFalse(onLaptop.contains { $0.hasPrefix("Move to Laptop") })
        let onDell = titles(MenuModel.build(inputs(frontX: 1100)))
        XCTAssertTrue(onDell.contains("Move to Laptop (1) — Full screen"))
        XCTAssertFalse(onDell.contains { $0.hasPrefix("Move to DELL") })
        let single = titles(MenuModel.build(inputs(screens: [lap])))
        XCTAssertFalse(single.contains { $0.hasPrefix("Move to") })
        XCTAssertFalse(zip(single, single.dropFirst()).contains { $0 == "-" && $1 == "-" }, "no doubled separators")
    }

    func testThreeScreensListBothOtherScreens() {
        let dell2 = screen(3, "DELL B", x: 2000)
        let moves = { (x: CGFloat) in self.titles(MenuModel.build(self.inputs(screens: [self.lap, self.dell, dell2], frontX: x)))
            .filter { $0.hasPrefix("Move to") } }
        XCTAssertEqual(moves(100), ["Move to DELL (2) — Full screen", "Move to DELL (2) — 90%", "Move to DELL (2) — same size",
                                    "Move to DELL B (3) — Full screen", "Move to DELL B (3) — 90%", "Move to DELL B (3) — same size"])
        XCTAssertEqual(moves(2100), ["Move to Laptop (1) — Full screen", "Move to Laptop (1) — 90%", "Move to Laptop (1) — same size",
                                     "Move to DELL (2) — Full screen", "Move to DELL (2) — 90%", "Move to DELL (2) — same size"])
    }

    func testRectangleRow() {
        func build(_ n: Int) -> [MenuNode] { var i = inputs(); i.rectangleShared = n; return MenuModel.build(i) }
        let t = titles(build(2))
        let row = t.firstIndex(of: "Rectangle is using 2 of your shortcuts…")
        XCTAssertNotNil(row)
        XCTAssertEqual(t[row! + 1], "Customize shortcuts…")
        guard case let .item(_, _, action, _) = build(2)[row!] else { return XCTFail("an item") }
        XCTAssertEqual(action, .customize)
        XCTAssertTrue(titles(build(1)).contains("Rectangle is using 1 of your shortcuts…"))
        XCTAssertFalse(titles(build(0)).contains { $0.hasPrefix("Rectangle") })
    }

    func testMoveToKeys() {
        let menu = MenuModel.build(inputs())
        XCTAssertEqual(submenu(menu, "Move to DELL (2) — 90%")?.keys, "⌥⌘2")
        XCTAssertEqual(submenu(menu, "Move to DELL (2) — Full screen")?.keys, "⌥⌘F⇧")
        XCTAssertEqual(submenu(menu, "Move to DELL (2) — same size")?.keys, "⌥⌘C⇧")
        let scopes = submenu(menu, "Move to DELL (2) — 90%")!.children
        guard case let .item(_, k, _, _) = scopes[3] else { return XCTFail() }
        XCTAssertEqual(k, "⌃⌥⌘2⇧", "everything")
        guard case let .item(_, _, action, _) = scopes[0] else { return XCTFail() }
        let ninety = Placer.fraction(0.9, on: .fixed(uuid: dell.uuid))
        XCTAssertEqual(action, .moveTo(uuid: dell.uuid, name: "DELL (2)", ninety, Selection(pid: 10, winId: 1), label: "DELL (2) (90%)"))
    }

    func testReferenceRowsAreNotDisabledItems() {
        guard let ref = submenu(MenuModel.build(inputs()), "Keyboard shortcuts")?.children else { return XCTFail() }
        for n in ref {
            switch n {
            case .header, .reference, .separator: break
            default: XCTFail("unexpected reference node \(n)")
            }
        }
    }

    func testReferenceContents() {
        let t = titles(MenuModel.shortcutReference(.defaults, derive(.defaults)))
        XCTAssertEqual(t, [
            "#THIS WINDOW",
            "⌥⌘ ← → ↑ ↓ | Left / right / top / bottom half",
            "⌥⌘F | Full screen", "⌥⌘G | 90%", "⌥⌘H | 60%", "⌥⌘C | Center (keep size)",
            "⌃⌘ ↑ → ← ↓ | Top left / top right / bottom left / bottom right",
            "-", "#ADD A KEY",
            "+ ⌃ | Every window of the app   (not corners: use the menu)",
            "+ ⇧ | On the next screen   (⌥⌘C⇧ = this window to the next screen, same size)",
            "+ ⌃⇧ | Every window of the app, on the next screen",
            "-", "#SCREENS   (1 = laptop, then monitors left to right)",
            "⌥⌘ 1 2 3 | This window → that screen (laptop full screen, monitors 90%)",
            "⌃⌥⌘ 1 2 3 | Every window of the app → that screen",
            "⌃⌥⌘ 1 2 3 ⇧ | EVERYTHING → that screen",
            "-", "#MENU",
            "⌃⌥⌘M | Open this menu under the mouse",
        ])
    }

    func testReferenceUngroupsCustomArrows() {
        var cfg = ShortcutConfig.defaults
        cfg.actions[.leftHalf] = Combo("j", .alt, .cmd)
        let t = titles(MenuModel.shortcutReference(cfg, derive(cfg)))
        XCTAssertTrue(t.contains("⌥⌘J | Left half"))
        XCTAssertTrue(t.contains("⌥⌘→ | Right half"))
    }

    func testRetryRowsOnTop() {
        let many = (1...10).map { "App — \($0)" }
        let t = titles(MenuModel.build(inputs(retry: (10, many))))
        XCTAssertEqual(t[0], "Retry 10 windows that didn't move")
        XCTAssertEqual(t[8], "App — 8")
        XCTAssertEqual(t[9], "and 2 more")
        XCTAssertEqual(t[10], "-")
        XCTAssertEqual(t[11], "Full screen")
        let one = titles(MenuModel.build(inputs(retry: (1, ["Safari — Doc"]))))
        XCTAssertEqual(Array(one.prefix(3)), ["Retry 1 window that didn't move", "Safari — Doc", "-"])
    }

    func testMoveToGoneScreenIsRefused() {
        let p = Placer.fraction(0.9, on: .fixed(uuid: dell.uuid))
        let a = MenuAction.moveTo(uuid: dell.uuid, name: "DELL (2)", p, .everything, label: "DELL (2) (90%)")
        XCTAssertEqual(MenuModel.resolve(a, screens: [lap]), .refused("DELL (2) isn't connected anymore"))
        XCTAssertEqual(MenuModel.resolve(a, screens: [lap, dell]), .run(.everything, p, label: "DELL (2) (90%)"))
    }

    func testNoFrontApp() {
        var i = inputs()
        i.ctx.front = nil
        i.ctx.frontWin = nil
        i.ctx.frontFrame = nil
        let children = submenu(MenuModel.build(i), "90%")!.children
        XCTAssertEqual(titles(children), ["Everything (5 windows)", "-", "Mail (2)"])
        XCTAssertTrue(titles(MenuModel.build(i)).contains("Move to Laptop (1) — Full screen"), "no front window: every screen")
    }
}
