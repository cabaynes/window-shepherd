import XCTest
@testable import WindowShepherdCore

/// Every new window goes to a free spot for its app as soon as it settles
/// (two sightings), and is never moved later.
@MainActor
final class NewWindowPlacementTests: XCTestCase {
    var sys: FakeWindowSystem!
    var store: LayoutStore!
    var spotStore: AppSpotStore!
    var clock = Date()
    var logFile: URL!
    var savedLog: URL!
    let lap = screen(1, "Built-in", x: 0, builtin: true)
    let dell = screen(2, "DELL", x: 1000, w: 2560, h: 1440)
    let ninety = UnitRect(x: 0.05, y: 0.05, w: 0.9, h: 0.9)
    let full = UnitRect(x: 0, y: 0, w: 1, h: 1)

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

    func make() -> Shepherd {
        let s = Shepherd(system: sys, store: store, spotStore: spotStore,
                         timing: MoveTiming(retryWaits: [0.05, 0.1], movePatience: 0.3),
                         restoreTiming: RestoreTiming(passes: [0.05, 0.15, 0.3], busyRecheck: 0.05, unsettledLimit: 1, patience: 0.3),
                         now: { [unowned self] in self.clock })
        s.start()
        return s
    }

    /// An app that launched `ago` seconds before now (an hour: no guessing period from its launch).
    func addApp(_ pid: pid_t, _ name: String, windows: [(UInt32, CGRect)], ago: TimeInterval = 3600, bundle: String? = nil) {
        sys.addApp(pid, name, windows: windows, bundle: bundle)
        sys.launched[pid] = clock.addingTimeInterval(-ago)
    }

    func rect(_ x: CGFloat) -> CGRect { CGRect(x: x, y: 125, width: 400, height: 300) }

    func drag(_ id: UInt32, to r: CGRect) {
        sys.locked {
            sys.mouseUsed = Date()
            let i = sys.windows.firstIndex { $0.id == id }!
            let w = sys.windows[i]
            sys.windows[i] = CGWindow(id: w.id, pid: w.pid, app: w.app, title: w.title, frame: r)
        }
    }

    func close(_ id: UInt32) { sys.locked { sys.windows.removeAll { $0.id == id } } }

    var key: String { Screens.setupKey(sys.screens()) }
    func spots(_ s: Shepherd, _ app: String) -> [AppSpot] { s.spots.spots[key]?["test." + app] ?? [] }
    func place(_ r: CGRect) -> Spot { Geometry.whereIs(r, in: sys.screens())! }
    var dell90: CGRect { Geometry.place(ninety, in: dell.frame) }

    /// A free Safari spot: recorded for a window that no longer exists, then released.
    func seedFreeSpot(_ s: Shepherd, _ unit: UnitRect, on scr: ScreenInfo, app: String = "Safari", bundle: String? = nil) {
        s.spots.record(key: key, bundle: bundle ?? "test." + app, window: "99", at: Spot(scr: scr.uuid, unit: unit), now: clock.timeIntervalSince1970)
        s.spots.release(existing: sys.allWindowIDs())
    }

    /// Two sightings of window `id`, its kind learned in between, then any job finishes.
    func settle(_ s: Shepherd, _ id: UInt32) async {
        s.tick()
        await waitUntil { s.isMainWindow(String(id)) != nil }
        s.tick()
        await waitUntil { !s.isBusy }
    }

    func log() -> String {
        Log.flush()
        return (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
    }

    func testNewWindowGoesToFreeSpot() async {
        let s = make()
        seedFreeSpot(s, ninety, on: dell)
        addApp(10, "Safari", windows: [(5, rect(100))], ago: 1)
        await settle(s, 5)
        XCTAssertEqual(sys.frameOf(5), dell90)
        XCTAssertTrue(s.book.restoredIds.contains("5"))
        XCTAssertTrue(Geometry.sameSpot(s.book.layouts[key]?["5"]?.spot, Spot(scr: dell.uuid, unit: ninety)), "recorded at once")
        XCTAssertEqual(spots(s, "Safari").count, 1, "its spot is held, not added again")
        XCTAssertTrue(s.spots.holds(key: key, window: "5"))
        XCTAssertTrue(log().contains("Safari window 5 → its spot on DELL (90% centered), opened at launch"), log())
    }

    func testNewWindowMidDayAlsoPlaced() async {
        addApp(10, "Safari", windows: [(1, rect(150))])
        let s = make()
        seedFreeSpot(s, ninety, on: dell)
        addApp(10, "Safari", windows: [(5, rect(100))])   // ⌘N, an hour after Safari launched
        await settle(s, 5)
        XCTAssertEqual(sys.frameOf(5), dell90)
        XCTAssertEqual(sys.frameOf(1), rect(150), "the window that was already open stays")
        XCTAssertTrue(log().contains("Safari window 5 → its spot on DELL (90% centered), new window"), log())
    }

    func testDraggedBeforeSecondSightingIsLeftAndBecomesASpot() async {
        let s = make()
        seedFreeSpot(s, ninety, on: dell)
        addApp(10, "Safari", windows: [(5, rect(100))], ago: 1)
        s.tick()
        await waitUntil { s.isMainWindow("5") != nil }
        drag(5, to: rect(1500))
        s.tick()
        await waitUntil { !s.isBusy }
        XCTAssertEqual(sys.frameOf(5), rect(1500), "yours: left where you put it")
        s.tick(); s.tick()
        await waitUntil { !s.isBusy }
        XCTAssertEqual(sys.frameOf(5), rect(1500))
        let list = spots(s, "Safari")
        XCTAssertEqual(list.count, 2, "\(list)")
        XCTAssertTrue(list.contains { Geometry.sameSpot($0.spot, place(rect(1500))) }, "\(list)")
        XCTAssertTrue(list.contains { Geometry.sameSpot($0.spot, Spot(scr: dell.uuid, unit: ninety)) }, "the free spot stays")
    }

    func testClickWithoutMovingStillPlaces() async {
        let s = make()
        seedFreeSpot(s, ninety, on: dell)
        addApp(10, "Safari", windows: [(5, rect(100))], ago: 1)
        s.tick()
        await waitUntil { s.isMainWindow("5") != nil }
        sys.locked { sys.mouseUsed = Date() }   // you click into it (its address bar) without moving it
        s.tick()
        await waitUntil { !s.isBusy }
        XCTAssertEqual(sys.frameOf(5), dell90)
    }

    func testTabSwitchIsNotANewWindow() async {
        addApp(20, "Finder", windows: [(1, rect(100))])
        let s = make()
        seedFreeSpot(s, ninety, on: dell, app: "Finder")
        s.tick()
        await waitUntil { s.isMainWindow("1") != nil }
        // ⌘T (or a click on a background tab): a new window id at the same frame; the old tab leaves the screen.
        sys.locked {
            sys.windows.removeAll { $0.id == 1 }
            sys.offSpace = [1]
            sys.windows.append(CGWindow(id: 2, pid: 20, app: "Finder", title: "Doc", frame: rect(100)))
        }
        await settle(s, 2)
        s.tick()
        await waitUntil { !s.isBusy }
        XCTAssertEqual(sys.frameOf(2), rect(100))
        XCTAssertEqual(sys.setCount(2), 0)
        XCTAssertFalse(s.spots.holds(key: key, window: "2"))
    }

    func testScreenChangeMidPlacementFreesItsSpot() async {
        sys.setDelay[5] = 0.5   // a slow app keeps the placement running
        let s = make()
        seedFreeSpot(s, ninety, on: dell)
        addApp(10, "Safari", windows: [(5, rect(100))], ago: 1)
        s.tick()
        await waitUntil { s.isMainWindow("5") != nil }
        s.tick()
        XCTAssertTrue(s.isBusy, "placing")
        let docked = key
        XCTAssertTrue(s.spots.holds(key: docked, window: "5"))
        try? await Task.sleep(nanoseconds: 100_000_000)
        sys.allScreens = [lap]
        s.screensChanged()
        XCTAssertFalse(s.spots.holds(key: docked, window: "5"), "never placed there: the spot is free again")
        await waitUntil { !s.isBusy }
    }

    func testNoFreeSpotLeavesIt() async {
        addApp(10, "Safari", windows: [(1, dell90)])
        let s = make()
        s.spots.record(key: key, bundle: "test.Safari", window: "1", at: Spot(scr: dell.uuid, unit: ninety), now: clock.timeIntervalSince1970)
        addApp(10, "Safari", windows: [(5, rect(100))])
        await settle(s, 5)
        s.tick()
        await waitUntil { !s.isBusy }
        XCTAssertEqual(sys.frameOf(5), rect(100))
        XCTAssertEqual(sys.setCount(5), 0)
    }

    func testNeverPlacedLater() async {
        addApp(10, "Safari", windows: [(1, dell90)])
        let s = make()
        s.spots.record(key: key, bundle: "test.Safari", window: "1", at: Spot(scr: dell.uuid, unit: ninety), now: clock.timeIntervalSince1970)
        addApp(10, "Safari", windows: [(5, rect(100))])
        await settle(s, 5)
        close(1)
        s.forgetSpots(existing: sys.allWindowIDs())   // its spot is free now
        for _ in 0..<5 {
            s.tick()
            await waitUntil { !s.isBusy }
        }
        XCTAssertFalse(s.spots.holds(key: key, window: "1"), "the spot was freed")
        XCTAssertEqual(sys.frameOf(5), rect(100), "open a while: never moved because a spot became free")
        XCTAssertEqual(sys.setCount(5), 0)
    }

    func testRefusedMoveFreesItsSpot() async {
        sys.failSet = [5]
        let s = make()
        seedFreeSpot(s, ninety, on: dell)
        addApp(10, "Safari", windows: [(5, rect(100))], ago: 1)
        await settle(s, 5)
        XCTAssertGreaterThan(sys.locked { sys.listCalls[10] ?? 0 }, 1, "it was tried")
        XCTAssertEqual(sys.frameOf(5), rect(100))
        XCTAssertFalse(s.spots.holds(key: key, window: "5"), "not placed: its spot is free again")
        XCTAssertEqual(spots(s, "Safari").count, 1)
    }

    func testDialogNotPlaced() async {
        sys.nonStandard = [5]
        let s = make()
        seedFreeSpot(s, ninety, on: dell)
        addApp(10, "Safari", windows: [(5, rect(100))], ago: 1)
        await settle(s, 5)
        XCTAssertEqual(s.isMainWindow("5"), false)
        s.tick()
        await waitUntil { !s.isBusy }
        XCTAssertEqual(sys.frameOf(5), rect(100))
        XCTAssertFalse(s.spots.holds(key: key, window: "5"))
    }

    func testWindowsOpenAtStartAfterRestart() async {
        // After a restart: Safari reopened two windows 5 s ago, before Window Shepherd started.
        addApp(10, "Safari", windows: [(5, rect(100)), (6, CGRect(x: 1500, y: 125, width: 2560, height: 775))], ago: 5)
        spotStore.save([key: ["test.Safari": [
            AppSpot(id: "A", scr: lap.uuid, unit: full, used: clock.timeIntervalSince1970 - 100),
            AppSpot(id: "B", scr: dell.uuid, unit: ninety, used: clock.timeIntervalSince1970 - 50),
        ]]])
        spotStore.flush()
        let s = make()
        XCTAssertNotNil(s.firstSeen["5"])
        XCTAssertNotNil(s.firstSeen["6"])
        await waitUntil { s.isMainWindow("5") != nil && s.isMainWindow("6") != nil }
        s.tick()   // counts as their second sighting
        await waitUntil { !s.isBusy }
        XCTAssertEqual(sys.frameOf(5), Geometry.place(full, in: lap.frame), "nearest spot: the laptop")
        XCTAssertEqual(sys.frameOf(6), dell90)
        let text = log()
        XCTAssertTrue(text.contains("Safari window 5 → its spot on Built-in (Full screen), opened at launch"), text)
        XCTAssertTrue(text.contains("Safari window 6 → its spot on DELL (90% centered), opened at launch"), text)
    }

    func testWindowsOpenAtStartFromAnOldLaunchAreLeft() async {
        addApp(10, "Safari", windows: [(5, rect(100))])   // launched an hour ago
        sys.offSpace = [6]                                // and one on another Space
        spotStore.save([key: ["test.Safari": [
            AppSpot(id: "A", scr: lap.uuid, unit: full, used: clock.timeIntervalSince1970),
            AppSpot(id: "B", scr: dell.uuid, unit: ninety, used: clock.timeIntervalSince1970),
        ]]])
        spotStore.flush()
        let s = make()
        XCTAssertNil(s.firstSeen["5"])
        await settle(s, 5)
        XCTAssertEqual(sys.frameOf(5), rect(100))
        sys.locked {   // you switch to its Space: it was open all along
            sys.offSpace = []
            sys.windows.append(CGWindow(id: 6, pid: 10, app: "Safari", title: "Doc", frame: rect(300)))
        }
        await settle(s, 6)
        s.tick()
        await waitUntil { !s.isBusy }
        XCTAssertEqual(sys.frameOf(6), rect(300))
        XCTAssertEqual(sys.setCount(6), 0)
    }

    func testKnownWindowNotPlaced() async {
        let s = make()
        seedFreeSpot(s, ninety, on: dell)
        // Back from another Space: it has a per-window entry for this setup.
        let spot = place(rect(100))
        s.book.layouts[key, default: [:]]["5"] = LayoutEntry(pid: 10, app: "Safari", scr: spot.scr, unit: spot.unit,
                                                             seen: clock.timeIntervalSince1970)
        addApp(10, "Safari", windows: [(5, rect(100))], ago: 1)
        await settle(s, 5)
        s.tick()
        await waitUntil { !s.isBusy }
        XCTAssertEqual(sys.frameOf(5), rect(100))
        XCTAssertEqual(sys.setCount(5), 0)
    }

    func testRelaunchSoonAfterQuitFillsItsSpot() async {
        addApp(10, "Safari", windows: [(1, dell90)])
        addApp(30, "Finder", windows: [(3, rect(600))])
        let s = make()
        s.spots.record(key: key, bundle: "test.Safari", window: "1", at: Spot(scr: dell.uuid, unit: ninety), now: clock.timeIntervalSince1970)
        await settle(s, 1)
        XCTAssertTrue(s.spots.holds(key: key, window: "1"))
        sys.locked { sys.windows.removeAll { $0.id == 1 }; sys.apps[10] = nil; sys.bundleOf[10] = nil }   // Safari quits
        s.tick()
        addApp(11, "Safari", windows: [(5, rect(100))], ago: 1)   // and reopens a few seconds later
        await settle(s, 5)
        s.tick()
        await waitUntil { !s.isBusy }
        XCTAssertEqual(sys.frameOf(5), dell90, "the spot its closed predecessor held")
    }

    func testCloseThenNewWindowFillsItsSpot() async {
        addApp(10, "Safari", windows: [(1, dell90), (2, rect(150))])
        let s = make()
        s.spots.record(key: key, bundle: "test.Safari", window: "1", at: Spot(scr: dell.uuid, unit: ninety), now: clock.timeIntervalSince1970)
        await settle(s, 1)
        close(1)                                          // ⌘W
        s.tick()
        addApp(10, "Safari", windows: [(5, rect(100))])   // ⌘N
        await settle(s, 5)
        XCTAssertEqual(sys.frameOf(5), dell90)
    }

    /// Window Shepherd relaunches (an update, a crash): Safari's one window sits in its only spot.
    func testRelaunchOfWindowShepherdKeepsOccupiedSpotsTaken() async {
        addApp(10, "Safari", windows: [(1, dell90)])
        addApp(30, "Finder", windows: [(3, rect(600))])
        store.save([key: ["1": LayoutEntry(pid: 10, app: "Safari", scr: dell.uuid, unit: ninety, seen: clock.timeIntervalSince1970)]])
        store.flush()
        spotStore.save([key: ["test.Safari": [AppSpot(id: "A", scr: dell.uuid, unit: ninety, used: clock.timeIntervalSince1970)]]])
        spotStore.flush()
        let s = make()
        XCTAssertTrue(s.spots.holds(key: key, window: "1"), "held again at launch")
        await settle(s, 1)
        addApp(10, "Safari", windows: [(5, rect(100))])   // ⌘N
        await settle(s, 5)
        XCTAssertEqual(sys.frameOf(5), rect(100), "not stacked onto the spot window 1 is sitting in")
    }

    /// The app repositions its own new window between sightings (no mouse): it still settles and is placed.
    func testAppSettlingItsOwnWindowIsStillPlaced() async {
        let s = make()
        seedFreeSpot(s, ninety, on: dell)
        addApp(10, "Safari", windows: [(5, rect(100))], ago: 1)
        s.tick()
        await waitUntil { s.isMainWindow("5") != nil }
        sys.locked {
            let i = sys.windows.firstIndex { $0.id == 5 }!
            sys.windows[i] = CGWindow(id: 5, pid: 10, app: "Safari", title: "Doc", frame: rect(200))
        }
        for _ in 0..<3 {
            s.tick()
            await waitUntil { !s.isBusy }
        }
        XCTAssertEqual(sys.frameOf(5), dell90)
    }

    func testWindowTheAppKeepsMovingIsLeftAfterThreeResets() async {
        let s = make()
        seedFreeSpot(s, ninety, on: dell)
        addApp(10, "Safari", windows: [(5, rect(100))], ago: 1)
        s.tick()
        await waitUntil { s.isMainWindow("5") != nil }
        for x in [200, 300, 400, 500] as [CGFloat] {   // a new spot at every sighting
            sys.locked {
                let i = sys.windows.firstIndex { $0.id == 5 }!
                sys.windows[i] = CGWindow(id: 5, pid: 10, app: "Safari", title: "Doc", frame: rect(x))
            }
            s.tick()
            await waitUntil { !s.isBusy }
        }
        XCTAssertTrue(s.notNew.contains("5"), "left for good")
        for _ in 0..<3 {   // it stops moving: still never placed
            s.tick()
            await waitUntil { !s.isBusy }
        }
        XCTAssertEqual(sys.frameOf(5), rect(500))
        XCTAssertEqual(sys.setCount(5), 0)
    }

    func testScreenChangeForgetsNewWindowsYouDragged() async {
        let s = make()
        seedFreeSpot(s, ninety, on: dell)
        addApp(10, "Safari", windows: [(5, rect(100))], ago: 1)
        s.tick()
        await waitUntil { s.isMainWindow("5") != nil }
        drag(5, to: rect(1500))
        s.tick()
        XCTAssertTrue(s.draggedNew.contains("5"))
        sys.allScreens = [lap]
        s.screensChanged()
        XCTAssertTrue(s.draggedNew.isEmpty, "where macOS puts it now isn't your spot")
        await waitUntil { !s.isBusy }
    }

    /// A new window can be in the window list a moment before it's in its app's own list.
    func testWindowLateToTheAXListIsStillPlaced() async {
        let s = make()
        seedFreeSpot(s, ninety, on: dell)
        sys.hiddenFromAX = [5]
        addApp(10, "Safari", windows: [(5, rect(100))], ago: 1)
        for _ in 0..<2 {
            s.tick()
            await waitUntil { s.kindsInFlight.isEmpty }
        }
        sys.locked { sys.hiddenFromAX = [] }
        for _ in 0..<2 {
            s.tick()
            await waitUntil { s.kindsInFlight.isEmpty && !s.isBusy }
        }
        XCTAssertEqual(s.isMainWindow("5"), true)
        XCTAssertEqual(sys.frameOf(5), dell90)
    }

    /// Late to its app's list, so the snapshot recorded where it opened; then the app moves it
    /// itself, and the snapshot sees that move at the tick it's placed. It keeps the spot it's
    /// being placed in: the app's move doesn't add a second one.
    func testAppMovingANewWindowAsItIsPlacedAddsNoSpot() async {
        let s = make()
        seedFreeSpot(s, ninety, on: dell)
        clock = clock.addingTimeInterval(120)   // past the guessing period after Window Shepherd started
        sys.hiddenFromAX = [5]
        addApp(10, "Safari", windows: [(5, rect(100))])   // ⌘N, an hour after Safari launched
        for _ in 0..<2 {
            s.tick()
            await waitUntil { s.kindsInFlight.isEmpty }
        }
        XCTAssertNotNil(s.book.layouts[key]?["5"], "the snapshot recorded where it opened")
        sys.locked {
            sys.hiddenFromAX = []
            let i = sys.windows.firstIndex { $0.id == 5 }!
            sys.windows[i] = CGWindow(id: 5, pid: 10, app: "Safari", title: "Doc", frame: rect(200))
        }
        for _ in 0..<3 {
            s.tick()
            await waitUntil { s.kindsInFlight.isEmpty && !s.isBusy }
        }
        XCTAssertEqual(sys.frameOf(5), dell90)
        let list = spots(s, "Safari")
        XCTAssertEqual(list.count, 1, "\(list)")
        XCTAssertTrue(s.spots.holds(key: key, window: "5"))
    }

    /// A sheet (never in its app's own list) is never placed and never becomes a spot.
    func testNewSheetIsNeverPlaced() async {
        let s = make()
        seedFreeSpot(s, ninety, on: dell)
        sys.hiddenFromAX = [5]
        addApp(10, "Safari", windows: [(5, rect(100))], ago: 1)
        for _ in 0..<6 {
            s.tick()
            await waitUntil { s.kindsInFlight.isEmpty && !s.isBusy }
        }
        XCTAssertEqual(s.isMainWindow("5"), false)
        XCTAssertEqual(sys.setCount(5), 0)
        XCTAssertEqual(spots(s, "Safari").count, 1, "only the free spot")
    }

    static let finder = "com.apple.finder"
    func finderSpots(_ s: Shepherd) -> [AppSpot] { s.spots.spots[key]?[Self.finder] ?? [] }

    /// Finder's Get Info panel is a standard window to macOS but has no green full-screen
    /// button: it's left where Finder put it.
    func testFinderGetInfoPanelIsNeverPlaced() async {
        let s = make()
        seedFreeSpot(s, ninety, on: dell, bundle: Self.finder)
        sys.noFullScreenButton = [5]
        addApp(20, "Finder", windows: [(5, rect(100))], bundle: Self.finder)
        await settle(s, 5)
        s.tick()
        await waitUntil { !s.isBusy }
        XCTAssertEqual(s.isMainWindow("5"), false)
        XCTAssertEqual(sys.frameOf(5), rect(100))
        XCTAssertEqual(sys.setCount(5), 0)
        XCTAssertFalse(s.spots.holds(key: key, window: "5"))
    }

    /// Dragging a Get Info panel doesn't make its place a Finder spot.
    func testDraggedFinderGetInfoPanelIsNotASpot() async {
        let s = make()
        sys.noFullScreenButton = [5]
        addApp(20, "Finder", windows: [(5, rect(100))], bundle: Self.finder)
        await settle(s, 5)
        clock = clock.addingTimeInterval(120)   // past the guessing period
        drag(5, to: rect(1500))
        for _ in 0..<3 {
            s.tick()
            await waitUntil { s.kindsInFlight.isEmpty && !s.isBusy }
        }
        XCTAssertEqual(sys.frameOf(5), rect(1500))
        XCTAssertEqual(finderSpots(s), [])
    }

    /// A real Finder window (it has the green button) is still placed.
    func testFinderWindowIsStillPlaced() async {
        let s = make()
        seedFreeSpot(s, ninety, on: dell, bundle: Self.finder)
        addApp(20, "Finder", windows: [(5, rect(100))], bundle: Self.finder)
        await settle(s, 5)
        XCTAssertEqual(sys.frameOf(5), dell90)
    }

    /// Only Finder: another app's window without the green button (a Photoshop document) is still placed.
    func testOtherAppsWindowWithoutFullScreenButtonIsStillPlaced() async {
        let s = make()
        seedFreeSpot(s, ninety, on: dell, app: "Photoshop")
        sys.noFullScreenButton = [5]
        addApp(30, "Photoshop", windows: [(5, rect(100))], ago: 1)
        await settle(s, 5)
        XCTAssertEqual(sys.frameOf(5), dell90)
    }

    func testUnitLabel() {
        XCTAssertEqual(Shepherd.unitLabel(ninety), "90% centered")
        XCTAssertEqual(Shepherd.unitLabel(full), "Full screen")
        XCTAssertEqual(Shepherd.unitLabel(UnitRect(x: 0.2, y: 0.2, w: 0.6, h: 0.6)), "60% centered")
        XCTAssertEqual(Shepherd.unitLabel(UnitRect(x: 0.1, y: 0.052, w: 0.4, h: 0.5)), "10%,5% 40×50%")
    }
}
