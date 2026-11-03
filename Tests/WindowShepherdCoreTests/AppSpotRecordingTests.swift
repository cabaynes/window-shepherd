import XCTest
@testable import WindowShepherdCore

/// App spots learn only from placements that were yours or Window Shepherd's.
@MainActor
final class AppSpotRecordingTests: XCTestCase {
    var sys: FakeWindowSystem!
    var store: LayoutStore!
    var spotStore: AppSpotStore!
    var clock = Date()
    let lap = screen(1, "Built-in", x: 0, builtin: true)
    let dell = screen(2, "DELL", x: 1000, w: 2560, h: 1440)
    let ninety = UnitRect(x: 0.05, y: 0.05, w: 0.9, h: 0.9)

    override func setUp() async throws {
        sys = FakeWindowSystem()
        sys.allScreens = [lap, dell]
        sys.main = lap
        store = LayoutStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
        spotStore = AppSpotStore(url: AppSpotStore.url(beside: store.url))
        clock = Date()
    }

    func make() -> Shepherd {
        let s = Shepherd(system: sys, store: store, spotStore: spotStore,
                         timing: MoveTiming(retryWaits: [0.05, 0.1], movePatience: 0.3),
                         restoreTiming: RestoreTiming(passes: [0.05, 0.15, 0.3], busyRecheck: 0.05, unsettledLimit: 1, patience: 0.3),
                         now: { [unowned self] in self.clock })
        s.start()
        return s
    }

    /// An app that launched long ago (no guessing period from its launch).
    func addApp(_ pid: pid_t, _ name: String, windows: [(UInt32, CGRect)]) {
        sys.addApp(pid, name, windows: windows)
        sys.launched[pid] = clock.addingTimeInterval(-3600)
    }

    func rect(_ x: CGFloat) -> CGRect { CGRect(x: x, y: 125, width: 400, height: 300) }

    func move(_ id: UInt32, to r: CGRect) {
        sys.locked {
            let i = sys.windows.firstIndex { $0.id == id }!
            let w = sys.windows[i]
            sys.windows[i] = CGWindow(id: w.id, pid: w.pid, app: w.app, title: w.title, frame: r)
        }
    }

    /// You drag it with the mouse.
    func drag(_ id: UInt32, to r: CGRect) {
        sys.locked { sys.mouseUsed = Date() }
        move(id, to: r)
    }

    var key: String { Screens.setupKey(sys.screens()) }
    func spots(_ s: Shepherd, _ app: String) -> [AppSpot] { s.spots.spots[key]?["test." + app] ?? [] }
    func place(_ r: CGRect) -> Spot { Geometry.whereIs(r, in: sys.screens())! }

    /// Safari window 1 seen twice at x 100 (its per-window entry), kind learned.
    func knownWindow() async -> Shepherd {
        addApp(10, "Safari", windows: [(1, rect(100))])
        let s = make()
        s.tick()
        await waitUntil { s.isMainWindow("1") != nil }
        XCTAssertEqual(s.isMainWindow("1"), true)
        XCTAssertNotNil(s.book.layouts[key]?["1"])
        return s
    }

    func testHotkeyMoveRecordsSpot() async {
        let s = await knownWindow()
        s.apply(Selection(pid: 10), placer: .fraction(0.9, on: .fixed(uuid: dell.uuid)), label: "DELL (90%)")
        await waitUntil { !s.isBusy }
        let list = spots(s, "Safari")
        XCTAssertEqual(list.count, 1)
        XCTAssertTrue(Geometry.sameSpot(list.first?.spot, Spot(scr: dell.uuid, unit: ninety)), "\(list)")
        s.tick()   // saved at most once per tick
        spotStore.flush()
        XCTAssertEqual(spotStore.load()?[key]?["test.Safari"]?.count, 1)
    }

    func testUserMoveOutsideGuessingRecordsSpot() async {
        let s = await knownWindow()
        move(1, to: rect(1500))
        s.tick(); s.tick()
        let list = spots(s, "Safari")
        XCTAssertEqual(list.count, 1)
        XCTAssertTrue(Geometry.sameSpot(list.first?.spot, place(rect(1500))))
    }

    func testAppOpenedWindowNeverRecords() async {
        let s = make()
        addApp(10, "Safari", windows: [(1, rect(1500))])
        s.tick()
        await waitUntil { s.isMainWindow("1") != nil }
        for _ in 0..<5 { s.tick() }
        XCTAssertNotNil(s.book.layouts[key]?["1"], "the per-window memory still records it")
        XCTAssertTrue(spots(s, "Safari").isEmpty)
    }

    func testMoveDuringAppLaunchIsAGuess() async {
        let s = await knownWindow()
        sys.launched[10] = clock
        move(1, to: rect(1500))
        s.tick(); s.tick()
        XCTAssertTrue(Geometry.sameSpot(s.book.layouts[key]?["1"]?.spot, place(rect(1500))), "the move was confirmed")
        XCTAssertTrue(spots(s, "Safari").isEmpty)
    }

    func testDragDuringGuessingCounts() async {
        let s = await knownWindow()
        sys.launched[10] = clock
        drag(1, to: rect(1500))
        s.tick(); s.tick()
        let list = spots(s, "Safari")
        XCTAssertEqual(list.count, 1)
        XCTAssertTrue(Geometry.sameSpot(list.first?.spot, place(rect(1500))))
    }

    func testMoveAfterWakeIsAGuess() async {
        let s = await knownWindow()
        s.didWake()
        move(1, to: rect(1500))
        s.tick(); s.tick()
        XCTAssertTrue(Geometry.sameSpot(s.book.layouts[key]?["1"]?.spot, place(rect(1500))), "the move was confirmed")
        XCTAssertTrue(spots(s, "Safari").isEmpty)
    }

    func testDialogNeverRecords() async {
        sys.nonStandard = [1]
        addApp(10, "Safari", windows: [(1, rect(100))])
        let s = make()
        s.tick()
        await waitUntil { s.isMainWindow("1") != nil }
        XCTAssertEqual(s.isMainWindow("1"), false)
        s.apply(Selection(pid: 10), placer: .fraction(0.9, on: .fixed(uuid: dell.uuid)), label: "DELL (90%)")
        await waitUntil { !s.isBusy }
        XCTAssertGreaterThanOrEqual(sys.frameOf(1)?.minX ?? 0, 1000, "it was moved")
        s.tick(); s.tick()
        XCTAssertTrue(spots(s, "Safari").isEmpty)
    }

    func testRevertRecordsSpotsButPlainRestoreDoesNot() async {
        addApp(10, "Safari", windows: [(1, rect(1100))])
        let s = make()
        s.tick()
        await waitUntil { s.isMainWindow("1") != nil }
        clock = clock.addingTimeInterval(120)   // in use long enough to freeze when you leave it
        sys.allScreens = [lap]
        move(1, to: rect(50))
        s.screensChanged()
        await waitUntil { !s.isBusy }
        sys.allScreens = [lap, dell]
        s.tick()
        await waitUntil(4) { !s.isBusy }
        XCTAssertEqual(sys.frameOf(1)?.minX ?? 0, 1100, accuracy: 0.5, "a plain restore put it back")
        XCTAssertTrue(spots(s, "Safari").isEmpty, "a restore to its own entry records no spot")
        XCTAssertNotNil(s.book.frozen[key]?.layout["1"])
        move(1, to: rect(1500))
        s.tick(); s.tick()
        s.revert()
        await waitUntil(4) { !s.isBusy }
        XCTAssertEqual(sys.frameOf(1)?.minX ?? 0, 1100, accuracy: 0.5, "reverted")
        let list = spots(s, "Safari")
        XCTAssertEqual(list.count, 1)
        XCTAssertTrue(Geometry.sameSpot(list.first?.spot, place(rect(1100))), "\(list)")
    }

    /// As in UndockedTests: Safari remembered on the Dell; unplug; Notes window 7
    /// opens on the built-in screen; plug the Dell back in.
    func testUndockedDefaultRecordsSpot() async {
        addApp(10, "Safari", windows: [(1, rect(1100))])
        let s = make()
        s.tick()
        sys.allScreens = [lap]
        move(1, to: rect(50))
        s.screensChanged()
        await waitUntil { !s.isBusy }
        addApp(30, "Notes", windows: [(7, rect(40))])
        s.tick(); s.tick()
        await waitUntil { s.isMainWindow("7") != nil }
        sys.allScreens = [lap, dell]
        s.tick()
        await waitUntil(4) { !s.isBusy }
        XCTAssertEqual(sys.frameOf(7), Geometry.place(ninety, in: dell.frame), "the undocked default placed it")
        let list = spots(s, "Notes")
        XCTAssertEqual(list.count, 1)
        XCTAssertTrue(Geometry.sameSpot(list.first?.spot, Spot(scr: dell.uuid, unit: ninety)), "\(list)")
    }
}
