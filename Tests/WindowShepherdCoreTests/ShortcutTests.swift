import XCTest
@testable import WindowShepherdCore

/// Ported one-for-one from window-mover/tests/test_shortcuts.lua.
final class ShortcutTests: XCTestCase {
    private func fmt(_ b: ShortcutBinding?) -> String { b?.combo.formatted ?? "nil" }

    private func hasOwner(_ problems: [Problem], _ label: String) -> Bool {
        problems.contains { $0.owners.contains { $0.contains(label) } }
    }

    func testFormatOrder() {
        XCTAssertEqual(Combo("g", .ctrl, .alt, .cmd, .shift).formatted, "⌃⌥⌘G⇧")
        XCTAssertEqual(Combo("left", .alt, .cmd).formatted, "⌥⌘←")
    }

    func testParseRoundtrip() {
        for b in derive(.defaults) {
            let c = Combo.parse(b.combo.formatted)
            XCTAssertNotNil(c, "parse failed for \(b.combo.formatted)")
            XCTAssertEqual(c?.id, b.combo.id, b.combo.formatted)
        }
    }

    func testDefaultsMatchToday() {
        let bs = derive(.defaults)
        XCTAssertEqual(fmt(bs.find(.action(.almost), .window)), "⌥⌘G")
        XCTAssertEqual(fmt(bs.find(.action(.almost), .app)), "⌃⌥⌘G")
        XCTAssertEqual(fmt(bs.find(.action(.almost), .window, next: true)), "⌥⌘G⇧")
        XCTAssertEqual(fmt(bs.find(.action(.almost), .app, next: true)), "⌃⌥⌘G⇧")
        XCTAssertEqual(fmt(bs.find(.action(.topLeft), .window)), "⌃⌘↑")
        XCTAssertEqual(fmt(bs.find(.action(.topLeft), .window, next: true)), "⌃⌘↑⇧")
        XCTAssertNil(bs.find(.action(.topLeft), .app), "no whole-app corner")
        XCTAssertEqual(fmt(bs.find(.screen, .window, screen: 2)), "⌥⌘2")
        XCTAssertEqual(fmt(bs.find(.screen, .app, screen: 2)), "⌃⌥⌘2")
        XCTAssertEqual(fmt(bs.find(.screen, .all, screen: 2)), "⌃⌥⌘2⇧")
        XCTAssertEqual(fmt(bs.find(.menu, .window)), "⌃⌥⌘M")
        for n in 1...9 { XCTAssertNotNil(bs.find(.screen, .window, screen: n), "screen \(n)") }
        XCTAssertEqual(bs.count, 8 * 4 + 4 * 2 + 9 * 3 + 1, "binding count")
    }

    func testDefaultsValid() {
        let problems = validate(.defaults)
        XCTAssertTrue(problems.isEmpty, problems.first?.why ?? "")
    }

    func testClashWithDerived() {
        var cfg = ShortcutConfig.defaults
        cfg.actions[.almost] = Combo("f", .ctrl, .alt, .cmd)
        let problems = validate(cfg)
        XCTAssertFalse(problems.isEmpty)
        XCTAssertTrue(hasOwner(problems, "Full screen") && hasOwner(problems, "90%"))
    }

    func testClashWithScreenNumberNotConnected() {
        var cfg = ShortcutConfig.defaults
        cfg.actions[.sixty] = Combo("3", .alt, .cmd)
        XCTAssertFalse(validate(cfg).isEmpty)
    }

    func testWeakBaseBlocked() {
        var cfg = ShortcutConfig.defaults
        cfg.actions[.sixty] = Combo("h", .shift)
        let problems = validate(cfg)
        XCTAssertFalse(problems.isEmpty)
        XCTAssertTrue(problems.contains { $0.why.contains("⌃") }, "why mentions ⌃/⌥/⌘")
    }

    func testModifiersRules() {
        var cfg = ShortcutConfig.defaults
        cfg.wholeApp = .shift
        cfg.nextScreen = .shift
        XCTAssertFalse(validate(cfg).isEmpty, "same modifier twice")
        cfg = .defaults
        cfg.wholeApp = .alt  // the screen base ⌥⌘ already has it
        XCTAssertFalse(validate(cfg).isEmpty, "screen base contains whole-app modifier")
    }

    func testWholeAppAbsentWhenInBase() {
        var cfg = ShortcutConfig.defaults
        cfg.wholeApp = .alt
        cfg.screenBase = [.ctrl, .cmd]
        let bs = derive(cfg)
        XCTAssertNil(bs.find(.action(.almost), .app), "⌥ already in ⌥⌘G")
        // ⌃⌘ arrows corners now gain a whole-app key, which collides with nothing else
        for p in validate(cfg) {
            XCTAssertFalse(p.why.contains("modifier"), "unexpected modifier problem: \(p.why)")
        }
    }

    func testIsDefault() {
        XCTAssertTrue(ShortcutConfig.defaults.isDefault)
        var cfg = ShortcutConfig.defaults
        cfg.actions[.sixty] = Combo("u", .alt, .cmd)
        XCTAssertFalse(cfg.isDefault)
        cfg = .defaults
        cfg.wholeApp = .alt
        XCTAssertFalse(cfg.isDefault)
        cfg = .defaults
        cfg.screenBase.insert(.ctrl)
        XCTAssertFalse(cfg.isDefault)
    }

    func testReservedSystemKeysBlocked() {
        var cfg = ShortcutConfig.defaults
        cfg.actions[.sixty] = Combo("tab", .cmd)
        XCTAssertFalse(validate(cfg).isEmpty, "⌘Tab")
        cfg.actions[.sixty] = Combo("`", .cmd)
        XCTAssertFalse(validate(cfg).isEmpty, "⌘`")
    }

    func testEntrySubscript() {
        var cfg = ShortcutConfig.defaults
        XCTAssertEqual(cfg[.action(.almost)], .combo(Combo("g", .alt, .cmd)))
        cfg[.wholeApp] = .mod(.alt)
        XCTAssertEqual(cfg.wholeApp, .alt)
        cfg[.screenBase] = .mods([.ctrl])
        XCTAssertEqual(cfg.screenBase, [.ctrl])
        XCTAssertEqual(Entry.action(.almost).key, "action:90%")
        XCTAssertEqual(Entry.screenBase.name, "Screens")
    }

    func testJSONShape() throws {
        let data = try JSONEncoder().encode(ShortcutConfig.defaults)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let actions = obj["actions"] as! [String: Any]
        let almost = actions["90%"] as! [String: Any]
        XCTAssertEqual(almost["key"] as? String, "g")
        XCTAssertEqual(almost["mods"] as? [String], ["alt", "cmd"])
        XCTAssertEqual(obj["screenBase"] as? [String], ["alt", "cmd"])
        XCTAssertEqual(try JSONDecoder().decode(ShortcutConfig.self, from: data), .defaults)
    }
}
