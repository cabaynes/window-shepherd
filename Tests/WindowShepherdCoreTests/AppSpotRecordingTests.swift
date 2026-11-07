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
        sys.locked { sys.mouseUsed = Date(); sys.mouseDragged = sys.mouseUsed }
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

    /// Revert pressed while another move runs waits for it, and still records spots.
    func testRevertThatWaitsForAMoveStillRecordsSpots() async {
        addApp(10, "Safari", windows: [(1, rect(1100))])
        addApp(20, "Finder", windows: [(2, rect(1600))])
        let s = make()
        s.tick()
        await waitUntil { s.isMainWindow("1") != nil }
        clock = clock.addingTimeInterval(120)
        sys.allScreens = [lap]
        move(1, to: rect(50)); move(2, to: rect(60))
        s.screensChanged()
        await waitUntil { !s.isBusy }
        sys.allScreens = [lap, dell]
        s.tick()
        await waitUntil(4) { !s.isBusy }
        move(1, to: rect(1500))
        s.tick(); s.tick()
        sys.setDelay = [2: 0.3]
        s.apply(Selection(pid: 20), placer: .fraction(0.9, on: .own), label: "90%")   // a slow move is running…
        XCTAssertTrue(s.isBusy)
        s.revert()                                                                    // …when you press Revert
        await waitUntil(4) { !s.isBusy && self.sys.frameOf(1)?.minX == 1100 }
        XCTAssertEqual(sys.frameOf(1)?.minX ?? 0, 1100, accuracy: 0.5, "reverted")
        let list = spots(s, "Safari")
        XCTAssertEqual(list.count, 1, "\(list)")
    }

    /// A Revert that waits for another move keeps its full patience: an app slow to answer
    /// is still retried, though the screen change was long ago.
    func testRevertThatWaitsKeepsItsPatience() async {
        addApp(10, "Safari", windows: [(1, rect(1100))])
        addApp(20, "Finder", windows: [(2, rect(1600))])
        let s = Shepherd(system: sys, store: store, spotStore: spotStore,
                         timing: MoveTiming(retryWaits: [0.05, 0.1], movePatience: 0.3),
                         restoreTiming: RestoreTiming(passes: [0.05, 0.15, 0.3], busyRecheck: 0.05, unsettledLimit: 1, patience: 1.5),
                         now: { [unowned self] in self.clock })
        s.start()
        s.tick()
        await waitUntil { s.isMainWindow("1") != nil }
        clock = clock.addingTimeInterval(120)
        sys.allScreens = [lap]
        move(1, to: rect(50)); move(2, to: rect(60))
        s.screensChanged()
        await waitUntil(4) { !s.isBusy }
        sys.allScreens = [lap, dell]
        s.tick()
        await waitUntil(4) { !s.isBusy }
        move(1, to: rect(1500))
        s.tick(); s.tick()
        clock = clock.addingTimeInterval(120)             // the screen change's patience is long gone
        sys.setDelay = [2: 0.3]
        s.apply(Selection(pid: 20), placer: .fraction(0.9, on: .own), label: "90%")
        s.revert()
        sys.locked { sys.listCalls[10] = 0; sys.listBehaviour[10] = .throwTimes(3) }   // Safari doesn't answer 3 times
        await waitUntil(4) { !s.isBusy && self.sys.frameOf(1)?.minX == 1100 }
        XCTAssertEqual(sys.frameOf(1)?.minX ?? 0, 1100, accuracy: 0.5, "retried and reverted")
    }

    /// A Revert whose patience is long over (its job went stale) no longer makes every later
    /// restore pass record spots.
    func testOldRevertMarkExpires() async {
        addApp(10, "Safari", windows: [(1, rect(1100))])
        let s = make()
        s.tick()
        await waitUntil { s.isMainWindow("1") != nil }
        s.tick(); s.tick()
        XCTAssertNotNil(s.book.layouts[key]?["1"])
        move(1, to: rect(1500))                                 // moved without the mouse
        s.revertPending = clock.timeIntervalSince1970 - 10      // a Revert that never finished, long ago
        s.restore()
        await waitUntil { !s.isBusy }
        XCTAssertEqual(sys.frameOf(1)?.minX ?? 0, 1100, accuracy: 0.5, "a plain restore put it back")
        XCTAssertTrue(spots(s, "Safari").isEmpty, "and recorded no spot: the old Revert is over")
        XCTAssertNil(s.revertPending)
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

    /// Its sheet moves with the window you drag; only the window is a spot.
    func testDraggingAWindowWithASheetMakesNoSpotForTheSheet() async {
        let sheet = CGRect(x: 1500, y: 150, width: 500, height: 300)
        addApp(10, "Safari", windows: [(1, Geometry.place(ninety, in: dell.frame)), (2, sheet)])
        sys.hiddenFromAX = [2]
        let s = make()
        for _ in 0..<6 {
            s.tick()
            await waitUntil { !s.kindsInFlight.contains(10) }
        }
        sys.locked {
            sys.mouseUsed = Date()
            sys.mouseDragged = sys.mouseUsed
            sys.windows = sys.windows.map { CGWindow(id: $0.id, pid: $0.pid, app: $0.app, title: $0.title, frame: $0.frame.offsetBy(dx: 0, dy: 40)) }
        }
        for _ in 0..<3 {
            s.tick()
            await waitUntil { !s.isBusy }
        }
        let list = spots(s, "Safari")
        XCTAssertFalse(list.contains { Geometry.sameSpot($0.spot, place(sheet.offsetBy(dx: 0, dy: 40))) }, "\(list)")
    }

    /// After Window Shepherd relaunches, moving a window once replaces the spot it sat in.
    func testMoveAfterRelaunchReplacesTheSpotItSatIn() async {
        addApp(10, "Safari", windows: [(1, rect(100))])
        let at = place(rect(100))
        store.save([key: ["1": LayoutEntry(pid: 10, app: "Safari", scr: at.scr, unit: at.unit, seen: clock.timeIntervalSince1970)]])
        store.flush()
        spotStore.save([key: ["test.Safari": [AppSpot(id: "A", scr: at.scr, unit: at.unit, used: clock.timeIntervalSince1970)]]])
        spotStore.flush()
        let s = make()
        s.tick()
        await waitUntil { s.isMainWindow("1") != nil }
        s.apply(Selection(pid: 10), placer: .fraction(0.9, on: .fixed(uuid: dell.uuid)), label: "DELL (90%)")
        await waitUntil { !s.isBusy }
        let list = spots(s, "Safari")
        XCTAssertEqual(list.count, 1, "\(list)")
        XCTAssertTrue(Geometry.sameSpot(list.first?.spot, Spot(scr: dell.uuid, unit: ninety)), "\(list)")
    }
}
