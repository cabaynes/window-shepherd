import XCTest
import Carbon.HIToolbox
@testable import WindowShepherdCore

/// A fake app menu tree.
final class FakeMenu {
    let title: String?, cmdChar: String?, mods: Int?, glyph: Int?
    var children: [FakeMenu]
    var delay: TimeInterval = 0
    init(_ title: String?, _ cmdChar: String? = nil, mods: Int? = nil, glyph: Int? = nil, _ children: [FakeMenu] = []) {
        self.title = title; self.cmdChar = cmdChar; self.mods = mods; self.glyph = glyph; self.children = children
    }
}

final class FakeMenuReader: MenuReader {
    var bars: [pid_t: FakeMenu] = [:]
    var reads = 0
    private let lock = NSLock()
    func menuBar(pid: pid_t) throws -> AnyObject? { bars[pid] }
    func read(_ e: AnyObject) throws -> MenuRead {
        let m = e as! FakeMenu
        lock.lock(); reads += 1; lock.unlock()
        if m.delay > 0 { Thread.sleep(forTimeInterval: m.delay) }
        return MenuRead(title: m.title, cmdChar: m.cmdChar, mods: m.mods, glyph: m.glyph, children: m.children)
    }
}

@MainActor
final class ClashScannerTests: XCTestCase {
    func bar(_ menus: FakeMenu...) -> FakeMenu { FakeMenu(nil, nil, menus) }

    func scan(_ reader: FakeMenuReader, apps: [(pid_t, String)], limits: ClashScanner.Limits = .init()) async
        -> (ClashSources?, [(Int, Int)]) {
        var done: ClashSources?
        var progress: [(Int, Int)] = []
        let s = ClashScanner(limits: limits, menuReader: reader)
        _ = s.start(combos: [], apps: apps.map { (pid: $0.0, name: $0.1) },
                    onUpdate: { _, d, t in progress.append((d, t)) }, onDone: { done = $0 })
        await waitUntil(5) { done != nil }
        return (done, progress)
    }

    func testCollectsShortcutsFromMenus() async {
        let r = FakeMenuReader()
        r.bars[1] = bar(FakeMenu("File", nil, [FakeMenu(nil, nil, [
            FakeMenu("New Window", "N"),
            FakeMenu("Export", nil, [FakeMenu(nil, nil, [FakeMenu("As PDF", "E", mods: 2)])]),
            FakeMenu("No shortcut"),
        ])]))
        let (sources, _) = await scan(r, apps: [(1, "Editor")])
        let mine = sources!.apps.filter { $0.app == "Editor" }
        XCTAssertEqual(Set(mine.map { "\($0.combo.formatted) \($0.what)" }), ["⌘N New Window", "⌥⌘E As PDF"])
        XCTAssertGreaterThanOrEqual(sources!.apps.count, 429 + 2, "built-in list included")
    }

    func testSlowAppIsSkippedOthersContinue() async {
        let r = FakeMenuReader()
        let slow = FakeMenu("Slow", "S")
        slow.delay = 0.5
        r.bars[1] = bar(FakeMenu("Edit", nil, [FakeMenu(nil, nil, [FakeMenu("After", "A"), slow])]))   // walked last-first, like the Lua
        r.bars[2] = bar(FakeMenu("File", nil, [FakeMenu(nil, nil, [FakeMenu("Save", "S")])]))
        let t0 = Date()
        let (sources, _) = await scan(r, apps: [(1, "Sluggish"), (2, "Quick")])
        XCTAssertLessThan(Date().timeIntervalSince(t0), 2)
        XCTAssertTrue(sources!.apps.contains { $0.app == "Quick" && $0.what == "Save" })
        XCTAssertFalse(sources!.apps.contains { $0.app == "Sluggish" }, "a read over 0.4 s skips the rest of that app")
    }

    func testDepthCap() async {
        let r = FakeMenuReader()
        // bar items are depth 1; menus 2; items 3; submenu 4; items 5; sub-submenu 6; its items 7 (not read)
        let deep = FakeMenu("Deep", "D")
        let d6 = FakeMenu(nil, nil, [deep])
        let d5 = FakeMenu("Level5", "5", [d6])
        let d4 = FakeMenu(nil, nil, [d5])
        let d3 = FakeMenu("Level3", "3", [d4])
        r.bars[1] = bar(FakeMenu("Top", nil, [FakeMenu(nil, nil, [d3])]))
        let (sources, _) = await scan(r, apps: [(1, "App")])
        let titles = Set(sources!.apps.filter { $0.app == "App" }.map(\.what))
        XCTAssertEqual(titles, ["Level3", "Level5"])
    }

    func testStopHaltsScan() async {
        let r = FakeMenuReader()
        for pid in 1...5 {
            let m = FakeMenu("Item", "I")
            m.delay = 0.1
            r.bars[pid_t(pid)] = bar(FakeMenu("Menu", nil, [FakeMenu(nil, nil, [m, m, m])]))
        }
        var done = false
        let s = ClashScanner(menuReader: r)
        let h = s.start(combos: [], apps: (1...5).map { (pid: pid_t($0), name: "App\($0)") },
                        onUpdate: { _, _, _ in }, onDone: { _ in done = true })
        try? await Task.sleep(nanoseconds: 150_000_000)
        h.stop()
        let readsAtStop = r.reads
        try? await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertFalse(done)
        XCTAssertLessThanOrEqual(r.reads, readsAtStop + 1)
    }

    func testProgressCounts() async {
        let r = FakeMenuReader()
        r.bars[1] = bar(); r.bars[2] = bar()
        let (_, progress) = await scan(r, apps: [(1, "A"), (2, "B")])
        XCTAssertEqual(progress.map(\.0), [0, 1, 2])
        XCTAssertEqual(Set(progress.map(\.1)), [2])
    }

    func testSymbolicConversion() {
        XCTAssertEqual(SystemShortcuts.combo(code: 49, carbonMods: UInt32(cmdKey))?.formatted, "⌘Space")
        XCTAssertEqual(SystemShortcuts.combo(code: 126, carbonMods: UInt32(controlKey))?.formatted, "⌃↑")
    }

    func testSystemMatchUsesNames() {
        let up = Combo("up", .ctrl, .cmd), g = Combo("g", .alt, .cmd), desk = Combo("3", .ctrl)
        let found = SystemShortcuts.match(combos: [up, g, desk], enabled: [up, desk], changedNames: [up.id: "Mission Control (custom)"])
        XCTAssertEqual(found, [SystemShortcut(combo: up, name: "Mission Control (custom)"),
                               SystemShortcut(combo: desk, name: "Switch to Desktop 3")])
    }

    func testUserKeyEquivalentsParse() {
        let list = UserKeyEquivalents.parse(["Merge All Windows": "@~m", "Bad": 5, "Empty": ""], app: "Safari (your custom shortcut)")
        XCTAssertEqual(list, [AppShortcut(combo: Combo("m", .alt, .cmd), app: "Safari (your custom shortcut)", what: "Merge All Windows")])
    }
}
