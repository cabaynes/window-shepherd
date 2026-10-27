import XCTest
@testable import WindowShepherdCore

/// Regression tests for the final whole-branch review.
@MainActor
final class FinalReviewFixTests: XCTestCase {
    var sys: FakeWindowSystem!
    var store: LayoutStore!
    var alerts: [String] = []
    let lap = screen(1, "Built-in", x: 0, builtin: true)
    let dell = screen(2, "DELL", x: 1000)

    override func setUp() async throws {
        sys = FakeWindowSystem()
        sys.allScreens = [lap, dell]
        sys.main = lap
        store = LayoutStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
        alerts = []
    }

    func make() -> Shepherd {
        let s = Shepherd(system: sys, store: store, timing: MoveTiming(retryWaits: [0.05, 0.1], movePatience: 0.2),
                         restoreTiming: RestoreTiming(passes: [0.05, 0.15, 0.3], busyRecheck: 0.05, unsettledLimit: 1, patience: 0.3))
        s.onAlert = { [unowned self] in self.alerts.append($0) }
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

    /// I3: a window you place while a restore job runs isn't put back by that job.
    func testWindowPlacedDuringRestoreJobIsLeftAlone() async {
        sys.addApp(10, "Safari", windows: [(1, rect(1100)), (2, rect(1300))])
        let s = make()
        s.tick()
        sys.allScreens = [lap]
        move(1, to: rect(50)); move(2, to: rect(80))
        s.screensChanged()
        await waitUntil { !s.isBusy }
        sys.setDelay = [1: 0.3, 2: 0.3]
        sys.allScreens = [lap, dell]
        s.tick()
        await waitUntil { self.sys.setCount(1) == 1 }   // the job is on window 1…
        s.book.restoredIds.insert("2")                  // …when you snap window 2 yourself
        await waitUntil { !s.isBusy }
        XCTAssertEqual(sys.setCount(2), 0, "the restore job must not move a window you just placed")
    }

    /// I1: a window that was on another Space during the restore is put back
    /// when it shows up, and its home isn't overwritten with the dumped spot.
    func testOffscreenWindowIsRestoredWhenItReappears() async {
        sys.addApp(10, "Safari", windows: [(1, rect(1100)), (2, rect(1300))])
        let s = make()
        s.tick()
        let key = Screens.setupKey([lap, dell])
        let home2 = s.book.layouts[key]?["2"]
        XCTAssertNotNil(home2)
        sys.allScreens = [lap]
        move(1, to: rect(50)); move(2, to: rect(80))
        s.screensChanged()
        await waitUntil { !s.isBusy }
        // Replug while window 2 sits on another Space (not listed anywhere).
        let hidden = sys.locked { sys.windows.first { $0.id == 2 }! }
        sys.locked { sys.windows.removeAll { $0.id == 2 } }
        sys.allScreens = [lap, dell]
        s.tick()
        await waitUntil { !s.isBusy }
        XCTAssertEqual(sys.setCount(2), 0)
        // You switch to that Space: window 2 shows up where macOS dumped it.
        sys.locked { sys.windows.append(hidden) }
        s.tick(); s.tick()
        await waitUntil { self.sys.setCount(2) == 1 }
        await waitUntil { !s.isBusy }
        XCTAssertEqual(sys.frameOf(2)!.minX, 1300, accuracy: 0.5, "put back on the Dell")
        s.tick(); s.tick()
        XCTAssertEqual(s.book.layouts[key]?["2"]?.scr, home2?.scr, "home not overwritten with the dumped spot")
    }
}
