import XCTest
@testable import WindowShepherdCore

/// Every move, restore, placement and Revert checks, about 2 s later, where the
/// window actually landed (CoreGraphics list). A miss is logged, left behind,
/// offered in the Retry row, and never sent again by itself.
@MainActor
final class LandingTests: XCTestCase {
    var sys: FakeWindowSystem!
    var store: LayoutStore!
    var spotStore: AppSpotStore!
    var clock = Date()
    var alerts: [String] = []
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
        alerts = []
        logFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".log")
        savedLog = Log.fileURL
        Log.fileURL = logFile
    }

    override func tearDown() async throws {
        Log.flush()
        Log.fileURL = savedLog
    }

    func make(spots: AppSpotMap = [:]) -> Shepherd {
        spotStore.save(spots)
        spotStore.flush()
        let s = Shepherd(system: sys, store: store, spotStore: spotStore,
                         timing: MoveTiming(retryWaits: [0.05, 0.1], movePatience: 0.3),
                         restoreTiming: RestoreTiming(passes: [0.05, 0.15, 0.3], busyRecheck: 0.05, unsettledLimit: 1, patience: 0.3),
                         now: { [unowned self] in self.clock })
        s.onAlert = { [unowned self] in self.alerts.append($0) }
        s.start()
        return s
    }

    /// An app that launched `ago` seconds before now (an hour: no guessing period from its launch).
    func addApp(_ pid: pid_t, _ name: String, windows: [(UInt32, CGRect)], ago: TimeInterval = 3600) {
        sys.addApp(pid, name, windows: windows)
        sys.launched[pid] = clock.addingTimeInterval(-ago)
    }

    func rect(_ x: CGFloat) -> CGRect { CGRect(x: x, y: 125, width: 400, height: 300) }

    func move(_ id: UInt32, to r: CGRect) {
        sys.locked {
            let i = sys.windows.firstIndex { $0.id == id }!
            let w = sys.windows[i]
            sys.windows[i] = CGWindow(id: w.id, pid: w.pid, app: w.app, title: w.title, frame: r)
        }
    }

    var key: String { Screens.setupKey(sys.screens()) }
    var lapKey: String { Screens.setupKey([lap]) }

    func log() -> String {
        Log.flush()
        return (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
    }

    /// Two seconds pass, then a settled tick.
    func later(_ s: Shepherd) {
        clock = clock.addingTimeInterval(2)
        s.tick()
    }

    /// Settled ticks until the window's kind is known.
    func learnKind(_ s: Shepherd, _ id: UInt32) async {
        s.tick()
        await waitUntil { s.isMainWindow(String(id)) != nil }
        s.tick()
        await waitUntil { !s.isBusy }
    }

    /// The keyboard: window 1 of Safari to 90% of its own screen.
    func snap(_ s: Shepherd) async {
        s.apply(Selection(pid: 10, winId: 1, quiet: true), placer: .fraction(0.9, on: .own), label: "Almost Maximize")
        await waitUntil { self.sys.setCount(1) == 1 && s.snapInFlight.isEmpty }
    }

    /// Window 1 remembered on the Dell, unplugged (dumped on the laptop), plugged back in: restored.
    func restoredOnce() async -> Shepherd {
        addApp(10, "Safari", windows: [(1, rect(1100))])
        let s = make()
        s.tick()   // second sighting: recorded
        sys.allScreens = [lap]
        move(1, to: rect(50))
        s.screensChanged()
        await waitUntil { !s.isBusy }
        sys.allScreens = [lap, dell]
        s.tick()
        await waitUntil(4) { !s.isBusy && self.sys.setCount(1) == 1 }
        return s
    }

    func testLandedMoveIsNotAMiss() async {
        addApp(10, "Safari", windows: [(1, rect(100))])
        let s = make()
        await snap(s)
        later(s)
        XCTAssertNil(s.retryOffer)
        XCTAssertFalse(s.flashing)
        XCTAssertTrue(s.book.leftBehind.isEmpty)
        XCTAssertTrue(alerts.isEmpty, "a keyboard snap stays quiet")
    }

    func testWrongPositionIsAMiss() async {
        addApp(10, "Safari", windows: [(1, rect(100))])
        sys.ignorePosition = [1]
        let s = make()
        await snap(s)
        s.tick()   // too soon to judge: it may still be animating
        XCTAssertFalse(s.book.leftBehind.contains("1"))
        later(s)
        XCTAssertTrue(s.book.leftBehind.contains("1"))
        XCTAssertEqual(s.retryOffer?.kind, .move)
        XCTAssertEqual(s.retryOffer?.missed, [10: [1]])
        XCTAssertTrue(s.flashing)
        XCTAssertTrue(log().contains("Safari window 1 didn't land: asked 50,64 900×698, ended at 100,125 900×698"), log())
        // Where it landed never becomes its per-window entry: it keeps the spot it was sent to.
        let sent = Geometry.whereIs(Geometry.place(ninety, in: lap.frame), in: sys.screens())
        XCTAssertTrue(Geometry.sameSpot(s.book.layouts[key]?["1"]?.spot, sent))
        XCTAssertNotNil(s.book.protect["1"])
        XCTAssertTrue(alerts.isEmpty, "no alert for a keyboard snap")
    }

    func testImposedSizeIsNotAMiss() async {
        addApp(10, "Safari", windows: [(1, rect(100))])
        sys.fixedSize = [1]
        let s = make()
        await snap(s)
        XCTAssertEqual(sys.frameOf(1)?.size, CGSize(width: 400, height: 300), "the app kept its size")
        later(s)
        XCTAssertNil(s.retryOffer)
        XCTAssertFalse(s.flashing)
        XCTAssertTrue(s.book.leftBehind.isEmpty)
        XCTAssertTrue(alerts.isEmpty)
    }

    func testShortResizableIsAMiss() async {
        addApp(10, "Safari", windows: [(1, rect(100))])
        sys.shrinkHeight = [1: 500]
        let s = make()
        await snap(s)
        later(s)
        XCTAssertTrue(s.book.leftBehind.contains("1"))
        XCTAssertEqual(s.retryOffer?.missed, [10: [1]])
        XCTAssertTrue(s.flashing)
    }

    func testNoAutomaticResend() async {
        addApp(10, "Safari", windows: [(1, rect(100))])
        sys.ignorePosition = [1]
        let s = make()
        await snap(s)
        for _ in 0..<5 {
            later(s)
            await waitUntil(0.2) { !s.isBusy }
        }
        XCTAssertEqual(sys.setCount(1), 1)
        XCTAssertTrue(s.book.leftBehind.contains("1"))
    }

    func testBulkMoveMissRetriesTheSameMove() async {
        addApp(10, "Safari", windows: [(1, rect(100)), (2, rect(150))])
        sys.ignorePosition = [1]
        let s = make()
        s.apply(Selection(pid: 10), placer: .fraction(0.9, on: .fixed(uuid: dell.uuid)), label: "DELL (90%)")
        await waitUntil { !s.isBusy }
        later(s)
        XCTAssertEqual(s.retryOffer?.missed, [10: [1]], "only the window that didn't land")
        sys.ignorePosition = []
        s.runRetry()
        await waitUntil { !s.isBusy }
        XCTAssertEqual(sys.setCount(1), 2)
        XCTAssertEqual(sys.setCount(2), 1)
        XCTAssertEqual(sys.frameOf(1)?.minX ?? 0, Geometry.place(ninety, in: dell.frame).minX, accuracy: 0.5)
        XCTAssertEqual(sys.frameOf(1)?.minY ?? 0, Geometry.place(ninety, in: dell.frame).minY, accuracy: 0.5)
    }

    /// Misses from two different moves in one check: Retry runs both moves, one after the other.
    func testRetryOfTwoDifferentMovesRunsBoth() async {
        addApp(10, "Safari", windows: [(1, rect(100))])
        addApp(20, "Finder", windows: [(2, rect(150))])
        sys.ignorePosition = [1, 2]
        let s = make()
        s.apply(Selection(pid: 10), placer: .fraction(0.9, on: .fixed(uuid: dell.uuid)), label: "DELL (90%)")
        await waitUntil { !s.isBusy }
        s.apply(Selection(pid: 20), placer: .fraction(0.9, on: .own), label: "90%")
        await waitUntil { !s.isBusy }
        later(s)
        XCTAssertEqual(s.retryOffer?.missed, [10: [1], 20: [2]])
        sys.ignorePosition = []
        sys.setDelay = [1: 0.2, 2: 0.2]
        s.runRetry()
        await waitUntil(4) { !s.isBusy && self.sys.setCount(1) == 2 && self.sys.setCount(2) == 2 }
        XCTAssertEqual(sys.setCount(1), 2, "Safari's move was tried again")
        XCTAssertEqual(sys.setCount(2), 2, "Finder's move was tried again")
        XCTAssertEqual(sys.frameOf(1)?.minX ?? 0, Geometry.place(ninety, in: dell.frame).minX, accuracy: 0.5)
    }

    /// Both moves in a Retry miss again: the Retry row offers both windows, not only the
    /// last move's (each move's finish used to replace the offer).
    func testRetryOfTwoMovesThatBothMissKeepsBoth() async {
        addApp(10, "Safari", windows: [(1, rect(100))])
        addApp(20, "Finder", windows: [(2, rect(150))])
        sys.ignorePosition = [1, 2]
        let s = make()
        s.apply(Selection(pid: 10), placer: .fraction(0.9, on: .fixed(uuid: dell.uuid)), label: "DELL (90%)")
        await waitUntil { !s.isBusy }
        s.apply(Selection(pid: 20), placer: .fraction(0.9, on: .own), label: "90%")
        await waitUntil { !s.isBusy }
        later(s)
        XCTAssertEqual(s.retryOffer?.missed, [10: [1], 20: [2]])
        sys.ignorePosition = []
        sys.failSet = [1, 2]                         // both refuse this time
        s.runRetry()
        await waitUntil(4) { !s.isBusy && self.sys.setCount(2) >= 2 }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(s.retryOffer?.missed, [10: [1], 20: [2]])
    }

    func testRestoreMissRetriesViaRestore() async {
        sys.ignorePosition = [1]
        let s = await restoredOnce()
        later(s)
        XCTAssertTrue(s.book.leftBehind.contains("1"))
        XCTAssertEqual(s.retryOffer?.kind, .restore)
        XCTAssertTrue(s.flashing)
        sys.ignorePosition = []
        s.runRetry()
        await waitUntil { !s.isBusy }
        XCTAssertEqual(sys.setCount(1), 2)
        XCTAssertEqual(sys.frameOf(1)?.minX ?? 0, 1100, accuracy: 1)
    }

    func testRestoreMissIsNotResentByLaterRestores() async {
        sys.ignorePosition = [1]
        let s = await restoredOnce()
        later(s)
        XCTAssertTrue(s.book.leftBehind.contains("1"))
        s.restore()   // a later pass (a window coming back from another Space, a resumed restore)
        await waitUntil { !s.isBusy }
        XCTAssertEqual(sys.setCount(1), 1)
    }

    func testMissDoesNotBecomeSpot() async {
        let s = make()
        // A free Safari spot on the Dell: recorded for a window that no longer exists, then released.
        s.spots.record(key: key, bundle: "test.Safari", window: "99", at: Spot(scr: dell.uuid, unit: ninety), now: clock.timeIntervalSince1970)
        s.spots.release(existing: sys.allWindowIDs())
        addApp(10, "Safari", windows: [(5, rect(100))], ago: 1)
        sys.ignorePosition = [5]
        await learnKind(s, 5)
        XCTAssertEqual(sys.setCount(5), 1, "placed")
        later(s)
        XCTAssertTrue(s.book.leftBehind.contains("5"))
        let list = s.spots.spots[key]?["test.Safari"] ?? []
        XCTAssertEqual(list.count, 1)
        XCTAssertTrue(Geometry.sameSpot(list.first?.spot, Spot(scr: dell.uuid, unit: ninety)), "the spot stays where it was")
        XCTAssertTrue(Geometry.sameSpot(s.book.layouts[key]?["5"]?.spot, Spot(scr: dell.uuid, unit: ninety)),
                      "its entry is where it was sent")
        // Retry is the same move into the spot.
        XCTAssertEqual(s.retryOffer?.kind, .move)
        sys.ignorePosition = []
        s.runRetry()
        await waitUntil { !s.isBusy }
        XCTAssertEqual(sys.frameOf(5), Geometry.place(ninety, in: dell.frame))
        XCTAssertEqual(s.spots.spots[key]?["test.Safari"]?.count, 1, "the retry moves into the same spot")
    }

    func testAppSpotRestoreMissFreesTheSpot() async {
        // Opened while docked: an entry for laptop + Dell only. Safari has a laptop spot.
        addApp(10, "Safari", windows: [(5, rect(1500))])
        let used = clock.timeIntervalSince1970
        let s = make(spots: [lapKey: ["test.Safari": [AppSpot(id: "L", scr: lap.uuid, unit: sixty, used: used)]]])
        await learnKind(s, 5)
        sys.ignorePosition = [5]
        sys.allScreens = [lap]
        move(5, to: rect(50))   // macOS pushes it onto the laptop
        s.screensChanged()
        await waitUntil(4) { !s.isBusy && self.sys.setCount(5) == 1 }
        XCTAssertTrue(s.spots.holds(key: lapKey, window: "5"))
        later(s)
        XCTAssertTrue(s.book.leftBehind.contains("5"))
        XCTAssertFalse(s.spots.holds(key: lapKey, window: "5"), "not in the spot: it stays free")
        XCTAssertNil(s.book.layouts[lapKey]?["5"], "no per-window entry from a miss")
        let list = s.spots.spots[lapKey]?["test.Safari"] ?? []
        XCTAssertEqual(list.map(\.id), ["L"])
        XCTAssertTrue(Geometry.sameSpot(list.first?.spot, Spot(scr: lap.uuid, unit: sixty)))
        sys.ignorePosition = []
        s.runRetry()
        await waitUntil { !s.isBusy }
        XCTAssertEqual(sys.frameOf(5), Geometry.place(sixty, in: lap.frame), "Retry puts it in the spot")
        XCTAssertTrue(s.spots.holds(key: lapKey, window: "5"))
    }

    func testRevertMissRecordsNoSpot() async {
        addApp(10, "Safari", windows: [(1, rect(1100))])
        let s = make()
        await learnKind(s, 1)
        clock = clock.addingTimeInterval(120)   // in use long enough to freeze when you leave it
        sys.allScreens = [lap]
        move(1, to: rect(50))
        s.screensChanged()
        await waitUntil { !s.isBusy }
        sys.allScreens = [lap, dell]
        s.tick()
        await waitUntil(4) { !s.isBusy }
        move(1, to: rect(1500))
        s.tick(); s.tick()
        clock = clock.addingTimeInterval(120)   // past the guessing period: a move the snapshot sees counts
        sys.ignorePosition = [1]
        s.revert()
        await waitUntil(4) { !s.isBusy }
        clock = clock.addingTimeInterval(1)
        s.tick()   // not checked yet: where it is isn't recorded
        clock = clock.addingTimeInterval(1)
        s.tick()
        XCTAssertTrue(s.book.leftBehind.contains("1"))
        XCTAssertEqual(s.retryOffer?.kind, .restore)
        XCTAssertEqual(s.spots.spots[key]?["test.Safari"] ?? [], [], "where it ended up is no spot")
        XCTAssertEqual(s.book.layouts[key]?["1"]?.spot.unit, s.book.frozen[key]?.layout["1"]?.unit, "its entry is the frozen one")
    }

    /// You drag it with the mouse.
    func drag(_ id: UInt32, to r: CGRect) {
        sys.locked { sys.mouseUsed = Date(); sys.mouseDragged = sys.mouseUsed }
        move(id, to: r)
    }

    /// A click (into a text field, a menu) doesn't move windows: the check still runs.
    func testClickBeforeTheCheckStillChecks() async {
        addApp(10, "Safari", windows: [(1, rect(100))])
        sys.ignorePosition = [1]
        let s = make()
        await snap(s)
        sys.locked { sys.mouseUsed = Date() }   // a click, no drag
        later(s)
        XCTAssertTrue(s.book.leftBehind.contains("1"))
        XCTAssertEqual(s.retryOffer?.missed, [10: [1]])
    }

    /// A tick with a window left behind, that also saves, reads the full window list once.
    func testOneFullWindowListReadPerTick() async {
        addApp(10, "Safari", windows: [(1, rect(100)), (2, rect(500))])
        sys.ignorePosition = [1]
        let s = make()
        await snap(s)
        later(s)
        XCTAssertTrue(s.book.leftBehind.contains("1"))
        move(2, to: rect(600))
        later(s)                                   // first sighting of the change
        sys.locked { sys.allIDsReads = 0 }
        later(s)                                   // second: the snapshot changes, so the tick saves
        XCTAssertEqual(sys.locked { sys.allIDsReads }, 1)
    }

    /// A drag in another window (selecting text, say) doesn't make this window's miss yours.
    func testDragInAnotherWindowStillChecks() async {
        addApp(10, "Safari", windows: [(1, rect(100)), (2, rect(600))])
        sys.ignorePosition = [1]
        let s = make()
        await snap(s)
        sys.locked { sys.mouseUsed = Date(); sys.mouseDragged = sys.mouseUsed; sys.mouseDraggedWindow = 2 }
        later(s)
        XCTAssertTrue(s.book.leftBehind.contains("1"))
    }

    func testDragBeforeTheCheckIsYours() async {
        addApp(10, "Safari", windows: [(1, rect(100))])
        let s = make()
        await learnKind(s, 1)
        await snap(s)
        drag(1, to: rect(300))   // right after the move, before it's checked
        later(s); later(s); later(s)
        XCTAssertFalse(s.book.leftBehind.contains("1"))
        XCTAssertNil(s.retryOffer)
        XCTAssertFalse(s.flashing)
        let there = Geometry.whereIs(rect(300), in: sys.screens())
        XCTAssertTrue(Geometry.sameSpot(s.book.layouts[key]?["1"]?.spot, there), "recorded where you put it")
        XCTAssertTrue((s.spots.spots[key]?["test.Safari"] ?? []).contains { Geometry.sameSpot($0.spot, there) },
                      "\(s.spots.spots[key]?["test.Safari"] ?? [])")
    }

    func testAppSpotMissStillFreesTheSpotAfterALongJob() async {
        addApp(10, "Safari", windows: [(5, rect(1500))])
        addApp(20, "Notes", windows: [(7, rect(1600))])
        let used = clock.timeIntervalSince1970
        let s = make(spots: [lapKey: ["test.Safari": [AppSpot(id: "L", scr: lap.uuid, unit: sixty, used: used)],
                                      "test.Notes": [AppSpot(id: "N", scr: lap.uuid, unit: ninety, used: used)]]])
        await learnKind(s, 5)
        await waitUntil { s.isMainWindow("7") != nil }
        sys.ignorePosition = [5]
        sys.setDelay[7] = 0.5   // Notes is slow: the restore keeps running
        sys.allScreens = [lap]
        move(5, to: rect(50)); move(7, to: rect(80))
        s.screensChanged()
        await waitUntil(4) { self.sys.setCount(5) == 1 }
        XCTAssertNotNil(s.runner.current, "Notes is still being moved")
        clock = clock.addingTimeInterval(11)   // past how long undo records are kept
        s.tick()
        await waitUntil(4) { !s.isBusy }
        later(s)
        XCTAssertTrue(s.book.leftBehind.contains("5"))
        XCTAssertFalse(s.spots.holds(key: lapKey, window: "5"), "not in the spot: it stays free")
        XCTAssertTrue(s.spots.holds(key: lapKey, window: "7"), "Notes landed in its spot")
    }

    func testRevertMissWithASlowAppRecordsNoSpot() async {
        addApp(10, "Safari", windows: [(1, rect(1100))])
        addApp(20, "Notes", windows: [(2, rect(1300))])
        let s = make()
        await learnKind(s, 1)
        await waitUntil { s.isMainWindow("2") != nil }
        // Freezes when you leave it without jumping the clock (a jump past a job's deadline clears it as stale).
        s.book.minActiveToFreeze = 0
        sys.allScreens = [lap]
        move(1, to: rect(50)); move(2, to: rect(80))
        s.screensChanged()
        await waitUntil { !s.isBusy }
        sys.allScreens = [lap, dell]
        s.tick()
        await waitUntil(4) { !s.isBusy }
        move(1, to: rect(1500)); move(2, to: rect(1700))
        s.tick(); s.tick()
        sys.ignorePosition = [1]
        sys.setDelay[2] = 0.5
        s.revert()
        await waitUntil(4) { self.sys.setCount(1) == 2 }
        XCTAssertNotNil(s.runner.current, "Notes is still being moved")
        clock = clock.addingTimeInterval(11)
        s.tick()
        await waitUntil(4) { !s.isBusy }
        later(s)
        XCTAssertTrue(s.book.leftBehind.contains("1"))
        XCTAssertEqual(s.spots.spots[key]?["test.Safari"] ?? [], [], "where it ended up is no spot")
    }

    func testDragAfterAppSpotMissClearsIt() async {
        addApp(10, "Safari", windows: [(5, rect(1500))])
        let used = clock.timeIntervalSince1970
        let s = make(spots: [lapKey: ["test.Safari": [AppSpot(id: "L", scr: lap.uuid, unit: sixty, used: used)]]])
        await learnKind(s, 5)
        sys.ignorePosition = [5]
        sys.allScreens = [lap]
        move(5, to: rect(50))
        s.screensChanged()
        await waitUntil(4) { !s.isBusy && self.sys.setCount(5) == 1 }
        later(s)
        XCTAssertTrue(s.book.leftBehind.contains("5"))
        XCTAssertTrue(s.flashing)
        drag(5, to: rect(300))
        later(s); later(s)
        XCTAssertFalse(s.book.leftBehind.contains("5"), "yours now")
        XCTAssertFalse(s.flashing)
    }

    func testLandingMissStaysOfferedAfterAnEmptyRestorePass() async {
        sys.ignorePosition = [1]
        let s = await restoredOnce()
        later(s)
        XCTAssertEqual(s.retryOffer?.missed, [10: [1]])
        s.restore()   // a later pass with nothing to put back
        await waitUntil { !s.isBusy }
        XCTAssertEqual(s.retryOffer?.missed, [10: [1]], "still offered")
        XCTAssertEqual(s.retryRows()?.count, 1)
    }

    func testMissBeforeAScreenChangeIsDropped() async {
        addApp(10, "Safari", windows: [(1, rect(100))])
        sys.ignorePosition = [1]
        let s = make()
        await snap(s)
        clock = clock.addingTimeInterval(1)
        sys.allScreens = [lap]
        s.screensChanged()
        await waitUntil { !s.isBusy }
        later(s); later(s)
        XCTAssertFalse(s.book.leftBehind.contains("1"), "its target was for the old setup")
    }

    /// The window list read right after a move can still show the old frame (an app that applies
    /// frames later): the spot follows where the check finds it.
    func testSpotIsWhereTheMoveLandedNotTheFirstRead() async {
        addApp(10, "Safari", windows: [(1, rect(100))], ago: 1)   // just launched: no snapshot records its spot
        sys.staleFrameOnce = [1]
        let s = make()
        await learnKind(s, 1)
        await snap(s)
        later(s); later(s)
        let landed = Geometry.whereIs(sys.frameOf(1)!, in: sys.screens())
        XCTAssertFalse(Geometry.sameSpot(landed, Geometry.whereIs(rect(100), in: sys.screens())), "it moved")
        let list = s.spots.spots[key]?["test.Safari"] ?? []
        XCTAssertEqual(list.count, 1, "\(list)")
        XCTAssertTrue(Geometry.sameSpot(list.first?.spot, landed), "\(list)")
    }
}
