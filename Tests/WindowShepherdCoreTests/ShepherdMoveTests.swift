import XCTest
@testable import WindowShepherdCore

@MainActor
final class ShepherdMoveTests: XCTestCase {
    var sys: FakeWindowSystem!
    var store: LayoutStore!
    var alerts: [String] = []
    var clock = Date()
    let lap = screen(1, "Built-in", x: 0, builtin: true)
    let dell = screen(2, "DELL", x: 1000)

    override func setUp() async throws {
        sys = FakeWindowSystem()
        sys.allScreens = [lap, dell]
        sys.main = lap
        store = LayoutStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
        alerts = []
        clock = Date()
    }

    func make() -> Shepherd {
        let s = Shepherd(system: sys, store: store, timing: MoveTiming(retryWaits: [0.05, 0.1]), now: { [unowned self] in self.clock })
        s.onAlert = { [unowned self] in self.alerts.append($0) }
        s.start()
        return s
    }

    func rect(_ x: CGFloat) -> CGRect { CGRect(x: x, y: 125, width: 400, height: 300) }

    func testThisWindowIsQuiet() async {
        sys.addApp(10, "Safari", windows: [(1, rect(100)), (2, rect(200))])
        sys.front = 10
        let s = make()
        s.doAction(.leftHalf, wholeApp: false, nextScreen: false)
        await waitUntil { self.sys.setCount(1) == 1 }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(sys.frameOf(1), CGRect(x: 0, y: 25, width: 500, height: 775))
        XCTAssertEqual(sys.setCount(2), 0)
        XCTAssertEqual(alerts, [])
        XCTAssertEqual(sys.activated, [])
        XCTAssertTrue(s.book.restoredIds.contains("1"))
    }

    func testSheetFallsBackToFocusedWindow() async {
        sys.addApp(10, "Safari", windows: [(1, rect(100))])
        sys.hiddenFromAX = [1]          // the front "window" is a sheet the app doesn't list
        sys.addApp(10, "Safari", windows: [(5, rect(1200))])
        sys.hiddenFromAX = [1]
        sys.focused[10] = 5
        sys.front = 10
        let s = make()
        s.doAction(.fullScreen, wholeApp: false, nextScreen: false)
        await waitUntil { self.sys.setCount(5) == 1 }
        XCTAssertEqual(sys.frameOf(5), dell.frame)
    }

    func testWholeAppActivatesAtEnd() async {
        sys.addApp(10, "Safari", windows: [(1, rect(100)), (2, rect(200))])
        sys.addApp(11, "Mail", windows: [(3, rect(300))])
        sys.front = 10
        let s = make()
        s.doAction(.almost, wholeApp: true, nextScreen: false)
        await waitUntil { self.alerts.count == 1 }
        await waitUntil { !self.sys.activated.isEmpty }
        XCTAssertEqual(alerts, ["Moved 2 windows → 90%"])
        XCTAssertEqual(sys.setCount(3), 0)
        XCTAssertEqual(sys.activated, [10])
    }

    func testEverythingDoesNotActivate() async {
        sys.addApp(10, "Safari", windows: [(1, rect(100))])
        sys.addApp(11, "Mail", windows: [(3, rect(300))])
        let s = make()
        s.apply(.everything, placer: .fraction(0.9, on: .fixed(uuid: dell.uuid)), label: "DELL (90%)")
        await waitUntil { self.alerts.count == 1 }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(alerts, ["Moved 2 windows → DELL (90%)"])
        XCTAssertEqual(sys.activated, [])
        XCTAssertTrue(dell.frame.contains(sys.frameOf(3)!))
    }

    // Chrome after ⌘`: the window you switched to has keyboard focus but isn't
    // raised, so the window list still has the laptop window first (live, 2026-10-20).
    func testMovesTheWindowWithKeyboardFocusNotTheFirstListed() async {
        sys.addApp(10, "Chrome", windows: [(1, rect(100)), (2, rect(1200))])
        sys.focused[10] = 2
        sys.front = 10
        let s = make()
        s.doAction(.almost, wholeApp: false, nextScreen: false)
        await waitUntil { self.sys.setCount(2) == 1 }
        XCTAssertEqual(sys.frameOf(2), Geometry.place(UnitRect(x: 0.05, y: 0.05, w: 0.9, h: 0.9), in: dell.frame))
        XCTAssertEqual(sys.setCount(1), 0)
    }

    // Two windows whose ids can't be read aren't the same window: use the focused one.
    func testUnreadableWindowIDsDontMatchEachOther() async {
        sys.addApp(10, "Chrome", windows: [(1, rect(100)), (2, rect(1200))])
        sys.unreadableIDs = [1, 2]
        sys.focused[10] = 2
        sys.front = 10
        let s = make()
        s.doAction(.almost, wholeApp: false, nextScreen: false)
        await waitUntil { self.sys.setCount(2) == 1 }
        XCTAssertEqual(sys.setCount(2), 1)
        XCTAssertEqual(sys.setCount(1), 0)
    }

    func testNextScreenIsTheOneAfterTheFocusedWindowsScreen() async {
        sys.addApp(10, "Chrome", windows: [(1, rect(100)), (2, rect(1200))])
        sys.focused[10] = 2     // on the Dell, so "next" is the laptop
        sys.front = 10
        let s = make()
        s.doAction(.almost, wholeApp: false, nextScreen: true)
        await waitUntil { self.sys.setCount(2) == 1 }
        XCTAssertEqual(sys.frameOf(2), Geometry.place(UnitRect(x: 0.05, y: 0.05, w: 0.9, h: 0.9), in: lap.frame))
        XCTAssertEqual(sys.setCount(1), 0)
    }

    func testNumberedScreenMovesTheFocusedWindow() async {
        sys.addApp(10, "Chrome", windows: [(1, rect(100)), (2, rect(1200))])
        sys.focused[10] = 2
        sys.front = 10
        let s = make()
        s.toNumberedScreen(1, scope: .window)
        await waitUntil { self.sys.setCount(2) == 1 }
        XCTAssertEqual(sys.setCount(1), 0)
    }

    func testNextScreenUsesFrontWindowsScreen() async {
        sys.addApp(10, "Safari", windows: [(1, rect(100))])
        sys.front = 10
        let s = make()
        s.doAction(.almost, wholeApp: false, nextScreen: true)
        await waitUntil { self.sys.setCount(1) == 1 }
        XCTAssertEqual(sys.frameOf(1), Geometry.place(UnitRect(x: 0.05, y: 0.05, w: 0.9, h: 0.9), in: dell.frame))
    }

    func testNumberedScreenScopes() async {
        sys.addApp(10, "Safari", windows: [(1, rect(100)), (2, rect(1100))])
        sys.addApp(11, "Mail", windows: [(3, rect(300))])
        sys.front = 10
        let s = make()
        s.toNumberedScreen(2, scope: .all)
        await waitUntil { self.alerts.count == 1 }
        XCTAssertEqual(alerts.last, "Moved 3 windows → DELL (90%)")
        let ninety = Placer.fraction(0.9, on: .own).frame(for: .zero, screens: [dell], main: dell)
        XCTAssertEqual(sys.frameOf(3), ninety)

        s.toNumberedScreen(1, scope: .app)
        await waitUntil { self.alerts.count == 2 }
        XCTAssertEqual(alerts.last, "Moved 2 windows → Laptop (full)")
        XCTAssertEqual(sys.frameOf(1), lap.frame)
        XCTAssertEqual(sys.frameOf(3), ninety, "Mail untouched")

        s.toNumberedScreen(3, scope: .window)
        XCTAssertEqual(alerts.last, "There's no screen 3")
    }

    func testRetryOfferLifecycle() async {
        sys.addApp(10, "Safari", windows: [(1, rect(100))])
        sys.listBehaviour[10] = .throwAlways
        let s = make()
        s.apply(.everything, placer: .fraction(1, on: .own), label: "Full screen")
        await waitUntil { self.alerts.count == 1 }
        XCTAssertEqual(alerts[0], "Moved 0 windows → Full screen\n(skipped, not responding: Safari)\nRetry from the ⧉ menu")
        let rows = s.retryRows()
        XCTAssertEqual(rows?.count, 1)
        XCTAssertEqual(rows?.titles, ["Safari — Doc"])

        sys.listBehaviour[10] = .ok
        s.runRetry()
        await waitUntil { self.alerts.count == 2 }
        XCTAssertEqual(alerts[1], "Moved 1 window → Full screen")
        XCTAssertNil(s.retryRows(), "a retry that got everything clears it")

        sys.listBehaviour[10] = .throwAlways
        s.apply(.everything, placer: .fraction(1, on: .own), label: "Full screen")
        await waitUntil { self.alerts.count == 3 }
        XCTAssertNotNil(s.retryRows())
        clock = clock.addingTimeInterval(121)
        XCTAssertNil(s.retryRows(), "expires after 2 minutes")
    }

    func testRetryTitlesTruncated() async {
        sys.addApp(10, "Safari", windows: [(1, rect(100))], title: String(repeating: "x", count: 80))
        sys.addApp(11, "Notes", windows: [(2, rect(200))], title: "")
        sys.listBehaviour = [10: .throwAlways, 11: .throwAlways]
        let s = make()
        s.apply(.everything, placer: .fraction(1, on: .own), label: "Full screen")
        await waitUntil { self.alerts.count == 1 }
        let titles = s.retryRows()?.titles ?? []
        XCTAssertEqual(titles.count, 2)
        XCTAssertEqual(titles[0], "Notes")
        XCTAssertEqual(titles[1].count, 58)
        XCTAssertTrue(titles[1].hasSuffix("…"))
    }

    func testMovedWindowsAreRecordedNow() async {
        sys.addApp(10, "Safari", windows: [(1, rect(100))])
        sys.front = 10
        let s = make()
        let saves = store.saveCount
        s.doAction(.rightHalf, wholeApp: true, nextScreen: false)
        await waitUntil { self.alerts.count == 1 }
        XCTAssertEqual(s.book.layouts[s.book.lastSetup!]?["1"]?.unit, UnitRect(x: 0.5, y: 0, w: 0.5, h: 1))
        XCTAssertGreaterThan(store.saveCount, saves)
    }

    func testScreenChangeMidMoveSavesNothing() async {
        sys.addApp(10, "Safari", windows: [(1, rect(100)), (2, rect(150)), (3, rect(200))])
        sys.setDelay = [1: 0.15, 2: 0.15, 3: 0.15]
        let s = make()
        let saves = store.saveCount
        s.apply(.everything, placer: .fraction(0.9, on: .fixed(uuid: dell.uuid)), label: "DELL (90%)")
        await waitUntil { self.sys.setCount(1) == 1 }
        s.book.lastSetup = "SOMETHING ELSE"      // what checkScreens does when the screens change
        let setsAtChange = sys.locked { sys.framesSet.count }
        try? await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertLessThanOrEqual(sys.locked { sys.framesSet.count }, setsAtChange + 1, "at most the in-flight window")
        XCTAssertEqual(store.saveCount, saves, "nothing saved for a setup that's gone")
        XCTAssertNil(s.retryRows())
    }

    func testHungAppNeverBlocksMainActor() async {
        sys.addApp(10, "Hung", windows: [(1, rect(100))])
        sys.addApp(11, "Fine", windows: [(2, rect(200))])
        sys.listBehaviour[10] = .sleep(3)
        sys.front = 10
        let s = make()
        s.doAction(.almost, wholeApp: true, nextScreen: false)   // job stuck on the hung app
        sys.front = 11
        let t0 = Date()
        s.doAction(.leftHalf, wholeApp: false, nextScreen: false)
        var mainRanAt: Date?
        let scheduled = Date()
        Task { @MainActor in mainRanAt = Date() }
        await waitUntil(2) { self.sys.setCount(2) == 1 }
        XCTAssertLessThan(Date().timeIntervalSince(t0), 0.3, "the snap didn't wait for the hung app")
        XCTAssertNotNil(mainRanAt)
        XCTAssertLessThan(mainRanAt!.timeIntervalSince(scheduled), 0.05)
    }

    func testMenuContext() {
        sys.addApp(11, "Mail", windows: [(3, rect(300))])
        sys.addApp(10, "Safari", windows: [(1, rect(100)), (2, rect(200))])
        sys.addApp(12, "Arc", windows: [(4, rect(400))])
        sys.front = 10
        let ctx = make().menuContext()
        XCTAssertEqual(ctx.front?.name, "Safari")
        XCTAssertEqual(ctx.front?.count, 2)
        XCTAssertEqual(ctx.frontWin, 1)
        XCTAssertEqual(ctx.total, 4)
        XCTAssertEqual(ctx.others.map(\.name), ["Arc", "Mail"])
    }
}
