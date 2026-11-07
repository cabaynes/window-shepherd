import XCTest
@testable import WindowShepherdCore

/// At a screen change, in either direction, a window with no per-window entry
/// for the new setup goes to a free spot for its app; the undocked default
/// only for apps with no spot. Revert never uses app spots.
@MainActor
final class AppSpotRestoreTests: XCTestCase {
    var sys: FakeWindowSystem!
    var store: LayoutStore!
    var spotStore: AppSpotStore!
    var clock = Date()
    var logFile: URL!
    var savedLog: URL!
    let lap = screen(1, "Built-in", x: 0, builtin: true)
    let dell = screen(2, "DELL", x: 1000, w: 2560, h: 1440)
    let ninety = UnitRect(x: 0.05, y: 0.05, w: 0.9, h: 0.9)
    let sixty = UnitRect(x: 0.2, y: 0.2, w: 0.6, h: 0.6)

    override func setUp() async throws {
        sys = FakeWindowSystem()
        sys.allScreens = [lap, dell]
        sys.main = lap
        store = LayoutStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
        spotStore = AppSpotStore(url: AppSpotStore.url(beside: store.url))
        clock = Date()
        logFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".log")
        savedLog = Log.fileURL
        Log.fileURL = logFile
    }

    override func tearDown() async throws {
        Log.flush()
        Log.fileURL = savedLog
    }

    /// Starts with these app spots on disk.
    func make(spots: AppSpotMap = [:]) -> Shepherd {
        spotStore.save(spots)
        spotStore.flush()
        let s = Shepherd(system: sys, store: store, spotStore: spotStore,
                         timing: MoveTiming(retryWaits: [0.05, 0.1], movePatience: 0.3),
                         restoreTiming: RestoreTiming(passes: [0.05, 0.15, 0.3], busyRecheck: 0.05, unsettledLimit: 1, patience: 0.3),
                         now: { [unowned self] in self.clock })
        s.start()
        return s
    }

    /// An app launched an hour ago: its windows aren't new.
    func addApp(_ pid: pid_t, _ name: String, windows: [(UInt32, CGRect)]) {
        sys.addApp(pid, name, windows: windows)
        sys.launched[pid] = clock.addingTimeInterval(-3600)
    }

    func rect(_ x: CGFloat) -> CGRect { CGRect(x: x, y: 125, width: 400, height: 300) }

    /// macOS (no mouse) moves a window.
    func move(_ id: UInt32, to r: CGRect) {
        sys.locked {
            let i = sys.windows.firstIndex { $0.id == id }!
            let w = sys.windows[i]
            sys.windows[i] = CGWindow(id: w.id, pid: w.pid, app: w.app, title: w.title, frame: r)
        }
    }

    var lapKey: String { Screens.setupKey([lap]) }
    var dockedKey: String { Screens.setupKey([lap, dell]) }
    var used: Double { clock.timeIntervalSince1970 }

    func log() -> String {
        Log.flush()
        return (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
    }

    /// Settled ticks until the window's kind is known.
    func learnKind(_ s: Shepherd, _ id: UInt32) async {
        s.tick()
        await waitUntil { s.isMainWindow(String(id)) != nil }
        s.tick()
        await waitUntil { !s.isBusy }
    }

    /// Docked with nothing open; unplug; open window `id` of `app` on the built-in
    /// screen; plug the Dell back in.
    func openWhileUndockedThenPlugIn(_ s: Shepherd, pid: pid_t, app: String, id: UInt32) async {
        s.tick()
        sys.allScreens = [lap]
        s.screensChanged()
        await waitUntil { !s.isBusy }
        addApp(pid, app, windows: [(id, rect(40))])
        await learnKind(s, id)
        sys.allScreens = [lap, dell]
        s.tick()
        await waitUntil(4) { !s.isBusy }
    }

    func testUnplugSendsWindowWithoutEntryToLaptopSpot() async {
        // Opened while docked: an entry for laptop + Dell only. Safari has a laptop spot.
        addApp(10, "Safari", windows: [(5, rect(1500))])
        let s = make(spots: [lapKey: ["test.Safari": [AppSpot(id: "L", scr: lap.uuid, unit: sixty, used: used)]]])
        await learnKind(s, 5)
        XCTAssertNotNil(s.book.layouts[dockedKey]?["5"])
        XCTAssertNil(s.book.layouts[lapKey]?["5"])
        sys.allScreens = [lap]
        move(5, to: rect(50))   // macOS pushes it onto the laptop
        s.screensChanged()
        await waitUntil(4) { !s.isBusy }
        XCTAssertEqual(sys.frameOf(5), Geometry.place(sixty, in: lap.frame))
        XCTAssertTrue(s.spots.holds(key: lapKey, window: "5"), "it holds the spot now")
        XCTAssertEqual(s.spots.spots[lapKey]?["test.Safari"]?.count, 1, "touched, not added to")
        let text = log()
        XCTAssertTrue(text.contains("Safari window 5 → its spot on Built-in (60% centered), no memory for this screen setup"), text)
    }

    func testRefusedMoveLeavesTheSpotFree() async {
        addApp(10, "Safari", windows: [(5, rect(1500))])
        sys.failSet = [5]
        let s = make(spots: [lapKey: ["test.Safari": [AppSpot(id: "L", scr: lap.uuid, unit: sixty, used: used)]]])
        await learnKind(s, 5)
        sys.allScreens = [lap]
        move(5, to: rect(50))
        s.screensChanged()
        await waitUntil(4) { !s.isBusy }
        XCTAssertGreaterThan(sys.locked { sys.listCalls[10] ?? 0 }, 1, "it was tried")
        XCTAssertEqual(sys.frameOf(5), rect(50))
        XCTAssertFalse(s.spots.holds(key: lapKey, window: "5"), "never in the spot: it isn't held")
        XCTAssertFalse(log().contains("Safari window 5 → its spot"), log())
    }

    func testPlugInPrefersAppSpotOverUndockedDefault() async {
        let s = make(spots: [dockedKey: ["test.Safari": [AppSpot(id: "D", scr: dell.uuid, unit: sixty, used: used)]]])
        XCTAssertTrue(s.undocked.enabled)
        await openWhileUndockedThenPlugIn(s, pid: 10, app: "Safari", id: 7)
        XCTAssertEqual(sys.frameOf(7), Geometry.place(sixty, in: dell.frame), "its app's spot, not the undocked 90%")
        XCTAssertEqual(s.spots.spots[dockedKey]?["test.Safari"]?.count, 1, "touched, not added to")
        XCTAssertFalse(log().contains("opened while undocked"), log())
    }

    /// Opened while undocked; at plug-in macOS happens to put it right at its app's Dell spot.
    func alreadyInItsSpotAtPlugIn() async -> Shepherd {
        let s = make(spots: [dockedKey: ["test.Safari": [AppSpot(id: "D", scr: dell.uuid, unit: sixty, used: used)]]])
        s.tick()
        sys.allScreens = [lap]
        s.screensChanged()
        await waitUntil { !s.isBusy }
        addApp(10, "Safari", windows: [(7, rect(40))])
        await learnKind(s, 7)
        sys.allScreens = [lap, dell]
        move(7, to: Geometry.place(sixty, in: dell.frame))
        s.tick()
        await waitUntil(4) { !s.isBusy }
        XCTAssertEqual(sys.setCount(7), 0, "already there: not moved")
        XCTAssertTrue(s.spots.holds(key: dockedKey, window: "7"))
        return s
    }

    func testAlreadyInItsSpotStaysThereOnRestoreNow() async {
        let s = await alreadyInItsSpotAtPlugIn()
        s.restoreNow()
        await waitUntil(4) { !s.isBusy }
        XCTAssertEqual(sys.setCount(7), 0, "never given the undocked default")
        XCTAssertEqual(s.spots.spots[dockedKey]?["test.Safari"]?.count, 1, "no spot added")
        XCTAssertTrue(Geometry.sameSpot(s.spots.spots[dockedKey]?["test.Safari"]?.first?.spot, Spot(scr: dell.uuid, unit: sixty)),
                      "the spot is unchanged")
    }

    func testAlreadyInItsSpotStaysThereOnRevert() async {
        let s = await alreadyInItsSpotAtPlugIn()
        s.book.frozen[dockedKey] = FrozenCopy(layout: [:], at: used)
        s.revert()
        await waitUntil(4) { !s.isBusy }
        XCTAssertEqual(sys.setCount(7), 0, "never given the undocked default")
        XCTAssertEqual(s.spots.spots[dockedKey]?["test.Safari"]?.count, 1, "no spot added")
        XCTAssertTrue(Geometry.sameSpot(s.spots.spots[dockedKey]?["test.Safari"]?.first?.spot, Spot(scr: dell.uuid, unit: sixty)),
                      "the spot is unchanged")
    }

    /// Two windows opened while undocked, one free spot for their app: one goes to it, the
    /// other gets the undocked default (precedence: entry → free spot → undocked default), which
    /// makes its place a spot.
    func testPlugInWithMoreWindowsThanFreeSpots() async {
        let s = make(spots: [dockedKey: ["test.Safari": [AppSpot(id: "D", scr: dell.uuid, unit: sixty, used: used)]]])
        s.tick()
        sys.allScreens = [lap]
        s.screensChanged()
        await waitUntil { !s.isBusy }
        addApp(10, "Safari", windows: [(7, rect(40)), (8, rect(500))])
        await learnKind(s, 7)
        await waitUntil { s.isMainWindow("8") != nil }
        sys.allScreens = [lap, dell]
        s.tick()
        await waitUntil(4) { !s.isBusy }
        let inSpot = [7, 8].filter { sys.frameOf($0) == Geometry.place(sixty, in: dell.frame) }
        XCTAssertEqual(inSpot.count, 1, "one window in the one spot")
        let other: UInt32 = inSpot.first == 7 ? 8 : 7
        XCTAssertEqual(sys.frameOf(other), Geometry.place(ninety, in: dell.frame), "the extra: the undocked default")
        XCTAssertEqual(s.spots.spots[dockedKey]?["test.Safari"]?.count, 2, "the undocked default's place is a spot")
        XCTAssertTrue(log().contains("Safari window \(other) → DELL (90% centered), opened while undocked"), log())
    }

    func testPlugInUndockedDefaultForAppWithoutSpots() async {
        let s = make()
        await openWhileUndockedThenPlugIn(s, pid: 30, app: "Notes", id: 7)
        XCTAssertEqual(sys.frameOf(7), Geometry.place(ninety, in: dell.frame))
        let list = s.spots.spots[dockedKey]?["test.Notes"] ?? []
        XCTAssertEqual(list.count, 1, "the undocked default placing it makes a spot")
        XCTAssertTrue(Geometry.sameSpot(list.first?.spot, Spot(scr: dell.uuid, unit: ninety)), "\(list)")
    }

    func testRevertIgnoresAppSpots() async {
        addApp(10, "Safari", windows: [(5, rect(1100)), (6, rect(1500))])
        let s = make(spots: [dockedKey: ["test.Safari": [
            AppSpot(id: "A", scr: dell.uuid, unit: sixty, used: used),
            AppSpot(id: "B", scr: dell.uuid, unit: ninety, used: used),
        ]]])
        await learnKind(s, 5)
        await waitUntil { s.isMainWindow("6") != nil }
        XCTAssertEqual(s.isMainWindow("6"), true)
        // Window 5 is in the frozen copy at x 1300; window 6 has no entry anywhere.
        let frozenAt = Geometry.whereIs(rect(1300), in: sys.screens())!
        s.book.frozen[dockedKey] = FrozenCopy(layout: ["5": LayoutEntry(pid: 10, app: "Safari", scr: frozenAt.scr, unit: frozenAt.unit, seen: used)],
                                              at: used)
        s.book.layouts[dockedKey]?["6"] = nil
        s.revert()
        await waitUntil(4) { !s.isBusy }
        XCTAssertEqual(sys.frameOf(5)?.minX ?? 0, 1300, accuracy: 0.5, "the frozen spot, not an app spot")
        XCTAssertEqual(sys.frameOf(6), rect(1500), "not in the frozen copy: Revert leaves it")
        XCTAssertEqual(sys.setCount(6), 0)
    }

    func testUndockedLogNamesEachWindow() async {
        let s = make()
        await openWhileUndockedThenPlugIn(s, pid: 30, app: "Notes", id: 7)
        let text = log()
        XCTAssertTrue(text.contains("Notes window 7 → DELL (90% centered), opened while undocked"), text)
        XCTAssertTrue(text.contains("1 window opened while undocked → DELL (90% centered)"), text)
    }
}
