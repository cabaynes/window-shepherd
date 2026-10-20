import XCTest
@testable import WindowShepherdCore

/// Ported from window-mover/tests/test_conflicts.lua (the Hammerspoon-source
/// tests are dropped with that source, per the design).
final class ConflictsTests: XCTestCase {
    private func f(_ c: Combo?) -> String { c?.formatted ?? "nil" }
    private func p(_ s: String) -> Combo { Combo.parse(s)! }

    func testFromAXMenu() {
        XCTAssertEqual(f(Conflicts.fromAXMenu(cmdChar: "S", modifiers: 0, glyph: nil)), "⌘S")
        XCTAssertEqual(f(Conflicts.fromAXMenu(cmdChar: "L", modifiers: 2, glyph: nil)), "⌥⌘L")
        XCTAssertEqual(f(Conflicts.fromAXMenu(cmdChar: nil, modifiers: 2, glyph: 100)), "⌥⌘←")
        XCTAssertEqual(f(Conflicts.fromAXMenu(cmdChar: "X", modifiers: 8 + 4, glyph: nil)), "⌃X")
        XCTAssertEqual(f(Conflicts.fromAXMenu(cmdChar: "N", modifiers: 1, glyph: nil)), "⌘N⇧")
        XCTAssertNil(Conflicts.fromAXMenu(cmdChar: nil, modifiers: 0, glyph: nil), "no shortcut")
        XCTAssertNil(Conflicts.fromAXMenu(cmdChar: "", modifiers: 0, glyph: nil), "empty char")
    }

    func testFromUserKeyEquivalent() {
        XCTAssertEqual(f(Conflicts.fromUserKeyEquivalent("@~g")), "⌥⌘G")
        XCTAssertEqual(f(Conflicts.fromUserKeyEquivalent("^@$k")), "⌃⌘K⇧")
        XCTAssertEqual(f(Conflicts.fromUserKeyEquivalent("@~\u{2190}")), "⌥⌘←")
        XCTAssertNil(Conflicts.fromUserKeyEquivalent(""))
    }

    func testFromSymbolic() {
        // NSEvent flags: shift 1<<17, ctrl 1<<18, alt 1<<19, cmd 1<<20
        XCTAssertEqual(f(Conflicts.fromSymbolic(keyName: "space", flags: 1 << 20)), "⌘Space")
        XCTAssertEqual(f(Conflicts.fromSymbolic(keyName: "left", flags: (1 << 18) | (1 << 20))), "⌃⌘←")
        XCTAssertEqual(f(Conflicts.fromSymbolic(keyName: "3", flags: (1 << 17) | (1 << 20))), "⌘3⇧")
    }

    func testCheckLevels() {
        let bindings = ["⌃⌘↑", "⌥⌘C", "⌥⌘G"].map(p)
        let sources = ClashSources(
            system: [SystemShortcut(combo: p("⌃⌘↑"), name: "Mission Control")],
            apps: [AppShortcut(combo: p("⌥⌘C"), app: "Safari", what: "Show JavaScript Console"),
                   AppShortcut(combo: p("⌥⌘Z"), app: "Safari", what: "Not bound by us")])
        let found = Conflicts.check(bindings: bindings, sources: sources)
        let up = found[p("⌃⌘↑").id]
        XCTAssertEqual(up?.first?.level, .block)
        XCTAssertTrue(up?.first?.text.contains("never work") ?? false)
        let c = found[p("⌥⌘C").id]
        XCTAssertEqual(c?.first?.level, .warn)
        XCTAssertEqual(c?.first?.text, "Safari: Show JavaScript Console. Yours will win.")
        XCTAssertNil(found[p("⌥⌘Z").id], "not bound by us")
        XCTAssertNil(found[p("⌥⌘G").id], "no clash")
    }

    func testBlocksSortFirst() {
        let found = Conflicts.check(bindings: [p("⌥⌘C")], sources: ClashSources(
            system: [SystemShortcut(combo: p("⌥⌘C"), name: "Something")],
            apps: [AppShortcut(combo: p("⌥⌘C"), app: "Safari", what: "Console")]))
        XCTAssertEqual(found[p("⌥⌘C").id]?.map(\.level), [.block, .warn])
    }

    func testCheckOneFindingPerApp() {
        let found = Conflicts.check(bindings: [p("⌥⌘U")], sources: ClashSources(system: [], apps: [
            AppShortcut(combo: p("⌥⌘U"), app: "Safari", what: "Show Page Source (menu)"),
            AppShortcut(combo: p("⌥⌘U"), app: "Safari", what: "Show Page Source"),
            AppShortcut(combo: p("⌥⌘U"), app: "Google Chrome", what: "View Source")]))
        XCTAssertEqual(found[p("⌥⌘U").id]?.count, 2, "one per app")
    }

    func testKnownListParses() {
        let k = KnownShortcuts.shared
        XCTAssertGreaterThan(k.apps.count, 50, "built-in list too small: \(k.apps.count)")
        for e in k.apps {
            XCTAssertTrue(e.combo.mods.contains(.ctrl) || e.combo.mods.contains(.alt) || e.combo.mods.contains(.cmd),
                          "no ⌃⌥⌘: \(e.app) \(e.combo.formatted)")
            XCTAssertFalse(e.what.isEmpty)
        }
        XCTAssertNotNil(k.system[64], "Spotlight id 64 named")
        XCTAssertEqual(k.apps.count, 429, "every entry parsed")
    }

    func testSystemDefaultNames() {
        XCTAssertEqual(SystemShortcutNames.defaultName(for: p("⌃3")), "Switch to Desktop 3")
        XCTAssertEqual(SystemShortcutNames.defaultName(for: p("⌘Space")), "Spotlight search")
        XCTAssertNil(SystemShortcutNames.defaultName(for: p("⌥⌘G")))
    }
}
