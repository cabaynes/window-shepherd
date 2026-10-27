import XCTest
@testable import WindowShepherdCore

@MainActor
final class ShepherdRestoreTests: XCTestCase {
    var sys: FakeWindowSystem!
    var store: LayoutStore!
    var alerts: [String] = []
    var busy: [Bool] = []
    var clock = Date()
    let lap = screen(1, "Built-in", x: 0, builtin: true)
    let dell = screen(2, "DELL", x: 1000)

    override func setUp() async throws {
        sys = FakeWindowSystem()
        sys.allScreens = [lap, dell]
        sys.main = lap
        store = LayoutStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
        alerts = []
        busy = []
        clock = Date()
    }

    func make(passes: [TimeInterval] = [0.05, 0.15, 0.3], patience: TimeInterval = 0.5) -> Shepherd {
        var timing = MoveTiming(retryWaits: [0.05, 0.1])
        timing.maxWait = 0.4
        timing.movePatience = 0.5
        let s = Shepherd(system: sys, store: store, timing: timing,
                         restoreTiming: RestoreTiming(passes: passes, busyRecheck: 0.05, unsettledLimit: 1, patience: patience),
                         now: { [unowned self] in self.clock })
        s.onAlert = { [unowned self] in self.alerts.append($0) }
        s.onBusyChanged = { [unowned self] in self.busy.append($0) }
        s.start()
        return s
    }

    func rect(_ x: CGFloat) -> CGRect { CGRect(x: x, y: 125, width: 400, height: 300) }

    func move(_ id: UInt32, to r: CGRect) {
        sys.locked {
            let i = sys.windows.firstIndex { $0.id == id }!
            let w = sys.windows[i]
            sys.windows[i] = CGWindow(id: w.id, pid: w.pid, app: w.app, title: w.title, frame: r)
        }
    }

    /// Two windows remembered on the Dell, then unplugged (dumped on the laptop).
    func rememberedThenUnplugged() async -> Shepherd {
        sys.addApp(10, "Safari", windows: [(1, rect(1100)), (2, rect(1300))])
        let s = make()
        s.tick()   // second sighting: recorded
        sys.allScreens = [lap]
        move(1, to: rect(50)); move(2, to: rect(80))
        s.screensChanged()
        await waitUntil { !s.isBusy }
        return s
    }

    func testUnplugReplugRestores() async {
        let s = await rememberedThenUnplugged()
        alerts = []
        sys.allScreens = [lap, dell]
        s.tick()
        await waitUntil { self.alerts.count == 1 }
        XCTAssertEqual(alerts, ["Restored 2 windows for this screen setup"])
        XCTAssertEqual(sys.frameOf(1)!.minX, 1100, accuracy: 0.5)
        XCTAssertEqual(sys.frameOf(2)!.minX, 1300, accuracy: 0.5)
        XCTAssertEqual(sys.frameOf(1)!.width, 400, accuracy: 0.5)
    }

    func testRestoreWaitsForSlowApp() async {
        sys.addApp(10, "Safari", windows: [(1, rect(1100)), (2, rect(1300))])
        let s = make(passes: [0.05], patience: 1.5)   // one pass: only patience can rescue it
        s.tick()
        sys.allScreens = [lap]
        move(1, to: rect(50)); move(2, to: rect(80))
        s.screensChanged()
        await waitUntil { !s.isBusy }
        sys.listBehaviour[10] = .throwTimes(sys.listCalls[10, default: 0] + 4)
        sys.allScreens = [lap, dell]
        s.tick()
        await waitUntil(4) { !s.isBusy }
        XCTAssertEqual(sys.frameOf(1)?.minX ?? 0, 1100, accuracy: 2)
    }

    func testInterruptedRestoreResumesAfterMove() async {
        sys.addApp(10, "Safari", windows: [(1, rect(1100)), (2, rect(1300))])
        sys.addApp(20, "Notes", windows: [(5, rect(60))])
        let s = make(passes: [0.05])
        s.tick()
        sys.allScreens = [lap]
        move(1, to: rect(50)); move(2, to: rect(80))
        s.screensChanged()
        await waitUntil { !s.isBusy }
        sys.setDelay[1] = 0.2
        sys.allScreens = [lap, dell]
        s.tick()
        await waitUntil { self.sys.setCount(1) >= 1 || s.runner.current != nil }
        try? await Task.sleep(nanoseconds: 120_000_000)   // the restore is moving window 1
        s.apply(Selection(pid: 20), placer: .fraction(0.9, on: .own), label: "90%")
        await waitUntil(4) { !s.isBusy }
        try? await Task.sleep(nanoseconds: 100_000_000)
        await waitUntil(4) { !s.isBusy }
        XCTAssertEqual(sys.frameOf(2)?.minX ?? 0, 1300, accuracy: 2, "the restore finished after the move")
    }

    func testUserMoveDuringPassesIsNotUndone() async {
        let s = await rememberedThenUnplugged()
        sys.allScreens = [lap, dell]
        s.tick()
        await waitUntil { self.sys.setCount(1) >= 1 }
        try? await Task.sleep(nanoseconds: 30_000_000)
        move(1, to: rect(200))    // you drag it back to the laptop
        await waitUntil { !s.isBusy }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(sys.frameOf(1), rect(200))
        XCTAssertEqual(sys.setCount(1), 1)
    }

    func testNoSnapshotWhileUnsettled() async {
        sys.addApp(10, "Safari", windows: [(1, rect(1100))])
        let s = make(passes: [0.5, 0.6, 0.7])
        sys.allScreens = [lap]
        move(1, to: rect(50))
        s.tick()
        let key = Screens.setupKey([lap])
        s.tick(); s.tick()
        XCTAssertNil(s.book.layouts[key]?["1"], "half-moved positions aren't recorded")
        XCTAssertFalse(s.book.settled)
    }

    func testUnsettledSafetyNet() async {
        sys.addApp(10, "Safari", windows: [(1, rect(1100))])
        let s = make(passes: [30, 31, 32])
        sys.allScreens = [lap]
        s.tick()
        XCTAssertFalse(s.book.settled)
        clock = clock.addingTimeInterval(2)   // past unsettledLimit (1 s in this test)
        s.tick()
        XCTAssertTrue(s.book.settled)
    }

    func testBusyWhilePassesPending() async {
        let s = await rememberedThenUnplugged()
        busy = []
        sys.allScreens = [lap, dell]
        s.tick()
        XCTAssertTrue(s.isBusy)
        await waitUntil { !s.isBusy }
        XCTAssertEqual(busy.first, true)
        XCTAssertEqual(busy.last, false)
        XCTAssertEqual(s.pendingPasses, 0)
    }

    func testSetupChangeStopsRunningJobAndClearsRetry() async {
        sys.addApp(10, "Safari", windows: [(1, rect(100)), (2, rect(150))])
        sys.setDelay = [1: 0.3, 2: 0.3]
        let s = make()
        s.apply(.everything, placer: .fraction(0.9, on: .fixed(uuid: dell.uuid)), label: "DELL (90%)")
        await waitUntil { self.sys.setCount(1) == 1 }
        sys.allScreens = [lap]
        s.screensChanged()
        try? await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertEqual(sys.setCount(2), 0, "the old setup's job stopped")
        XCTAssertNil(s.retryOffer)
    }

    func testRestoreDefersWhileJobRuns() async {
        let s = await rememberedThenUnplugged()
        sys.allScreens = [lap, dell]
        let key = Screens.setupKey([lap, dell])
        s.book.lastSetup = key            // pretend the change was already handled
        s.book.settled = true
        sys.addApp(11, "Slow", windows: [(9, rect(500))])
        sys.setDelay = [9: 0.4]
        s.apply(Selection(pid: 11), placer: .fraction(1, on: .own), label: "Full screen")
        s.restoreNow()
        XCTAssertEqual(s.pendingPasses, 1, "re-checks shortly instead of interrupting the move")
        await waitUntil { self.sys.setCount(1) == 1 }
        XCTAssertEqual(sys.setCount(9), 1, "the move finished first")
    }

    func testStaleJobCleared() async {
        sys.addApp(10, "Hung", windows: [(1, rect(100))])
        sys.listBehaviour[10] = .sleep(1)
        let s = make()
        s.apply(Selection(pid: 10), placer: .fraction(1, on: .own), label: "Full screen")
        XCTAssertTrue(s.isBusy)
        clock = clock.addingTimeInterval(30)   // past the job's 11 s deadline + 5 s
        s.tick()
        XCTAssertFalse(s.isBusy)
    }

    func testPausedTickDoesNothing() {
        sys.addApp(10, "Safari", windows: [(1, rect(1100))])
        let s = make()
        s.paused = true
        sys.allScreens = [lap]
        s.tick()
        XCTAssertNotEqual(s.book.lastSetup, Screens.setupKey([lap]))
    }
}
