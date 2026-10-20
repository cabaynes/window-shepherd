import XCTest
@testable import WindowShepherdCore

final class SettingsLogicTests: XCTestCase {
    let noSystem: ([Combo]) -> [SystemShortcut] = { _ in [] }
    let safariC = AppShortcut(combo: Combo("c", .alt, .cmd), app: "Safari", what: "Show JavaScript Console")

    func testInternalClashBlockedNamesOwner() {
        var cand = ShortcutConfig.defaults
        cand.actions[.almost] = Combo("f", .ctrl, .alt, .cmd)
        guard case let .blocked(why) = judge(candidate: cand, entry: .action(.almost), sources: ClashSources(), systemCheck: noSystem)
        else { return XCTFail("expected blocked") }
        XCTAssertTrue(why.contains("Full screen"), why)
    }

    func testSystemClashBlocked() {
        var cand = ShortcutConfig.defaults
        cand.actions[.topLeft] = Combo("up", .ctrl, .alt)
        let system: ([Combo]) -> [SystemShortcut] = { combos in
            combos.filter { $0 == Combo("up", .ctrl, .alt) }.map { SystemShortcut(combo: $0, name: "Mission Control") }
        }
        let v = judge(candidate: cand, entry: .action(.topLeft), sources: ClashSources(), systemCheck: system)
        XCTAssertEqual(v, .blocked("⌃⌥↑: macOS takes this first, so it would never work: Mission Control"))
    }

    func testAppClashWarns() {
        let v = judge(candidate: .defaults, entry: .action(.center), sources: ClashSources(apps: [safariC]), systemCheck: noSystem)
        XCTAssertEqual(v, .warn(["⌥⌘C — Safari: Show JavaScript Console. Yours will win."]))
        XCTAssertEqual(judge(candidate: .defaults, entry: .action(.almost), sources: ClashSources(apps: [safariC]), systemCheck: noSystem),
                       .ok, "an entry that doesn't touch ⌥⌘C")
        if case .warn = judge(candidate: .defaults, entry: nil, sources: ClashSources(apps: [safariC]), systemCheck: noSystem) {} else {
            XCTFail("reset all considers every binding")
        }
    }

    func testDerivedChipCarriesWarning() {
        let wholeAppC = AppShortcut(combo: Combo("c", .ctrl, .alt, .cmd), app: "Xcode", what: "Something")
        let vm = settingsVM(config: .defaults, sources: ClashSources(apps: [wholeAppC]), systemCheck: noSystem)
        let center = vm.rows.first { $0.entry == .action(.center) }!
        XCTAssertNil(center.level)
        XCTAssertEqual(center.chips[0], ChipVM(label: "whole app", keys: "⌃⌥⌘C", level: .warn, text: "Xcode: Something. Yours will win."))
        XCTAssertEqual(center.chips[1].keys, "⌥⌘C⇧")
        XCTAssertEqual(center.chips[2].keys, "⌃⌥⌘C⇧")
    }

    func testCornersHaveMenuOnlyChip() {
        let vm = settingsVM(config: .defaults, sources: ClashSources(), systemCheck: noSystem)
        let tl = vm.rows.first { $0.entry == .action(.topLeft) }!
        XCTAssertEqual(tl.section, "Corners")
        XCTAssertEqual(tl.chips[0], ChipVM(label: "whole app", keys: nil, level: nil, text: nil))
        XCTAssertEqual(vm.rows.first!.section, "This window")
        XCTAssertEqual(vm.rows.count, 12)
        XCTAssertTrue(vm.rows.allSatisfy(\.isDefault))
        XCTAssertEqual(vm.menu.name, "Open the menu under the mouse")
        XCTAssertEqual(vm.menu.keys, "⌃⌥⌘M")
    }

    func testScreenChipsUseN() {
        let vm = settingsVM(config: .defaults, sources: ClashSources(), systemCheck: noSystem)
        XCTAssertEqual(vm.screenChips.map(\.keys), ["⌥⌘n", "⌃⌥⌘n", "⌃⌥⌘n⇧"])
        XCTAssertEqual(vm.screenChips.map(\.label), ["this window", "whole app", "everything"])
    }

    func testIsDefaultFlag() {
        var cfg = ShortcutConfig.defaults
        cfg.actions[.sixty] = Combo("u", .alt, .cmd)
        let vm = settingsVM(config: cfg, sources: ClashSources(), systemCheck: noSystem)
        XCTAssertFalse(vm.rows.first { $0.entry == .action(.sixty) }!.isDefault)
        XCTAssertEqual(vm.rows.first { $0.entry == .action(.sixty) }!.keys, "⌥⌘U")
    }
}
