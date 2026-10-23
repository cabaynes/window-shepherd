import XCTest
@testable import WindowShepherdCore

/// Regression tests for the Checkpoint A review findings.
@MainActor
final class CheckpointAFixTests: XCTestCase {
    var sys: FakeWindowSystem!
    var store: LayoutStore!
    let lap = screen(1, "Built-in", x: 0, builtin: true)
    let dell = screen(2, "DELL", x: 1000)

    override func setUp() async throws {
        sys = FakeWindowSystem()
        sys.allScreens = [lap, dell]
        sys.main = lap
        store = LayoutStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
    }

    func make() -> Shepherd {
        let s = Shepherd(system: sys, store: store, timing: MoveTiming(retryWaits: [0.05, 0.1]),
                         restoreTiming: RestoreTiming(passes: [5, 6, 7], busyRecheck: 5, unsettledLimit: 60))
        s.start()
        return s
    }

    func rect(_ x: CGFloat) -> CGRect { CGRect(x: x, y: 125, width: 400, height: 300) }

    func testScreenChangeDuringBulkStepDoesNotLeakIntoNewSetup() async {
        sys.addApp(10, "Safari", windows: [(1, rect(100))])
        sys.setDelay = [1: 0.3]
        let s = make()
        s.apply(.everything, placer: .fraction(0.9, on: .fixed(uuid: dell.uuid)), label: "DELL (90%)")
        try? await Task.sleep(nanoseconds: 100_000_000)   // the step is in flight
        sys.allScreens = [lap]
        s.screensChanged()
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(s.book.restoredIds.contains("1"), "a step from the old setup must not mark windows in the new one")
    }

    func testScreenChangeDuringSnapDoesNotLeakIntoNewSetup() async {
        sys.addApp(10, "Safari", windows: [(1, rect(100))])
        sys.setDelay = [1: 0.3]
        sys.front = 10
        let s = make()
        s.doAction(.leftHalf, wholeApp: false, nextScreen: false)
        try? await Task.sleep(nanoseconds: 100_000_000)
        sys.allScreens = [lap]
        s.screensChanged()
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(s.book.restoredIds.contains("1"))
    }

    func testSnapOnHungAppDoesNotDelayOtherApps() async {
        sys.addApp(10, "Hung", windows: [(1, rect(100))])
        sys.addApp(11, "Fine", windows: [(2, rect(200))])
        sys.listBehaviour[10] = .sleep(1)
        sys.front = 10
        let s = make()
        s.doAction(.leftHalf, wholeApp: false, nextScreen: false)
        s.doAction(.rightHalf, wholeApp: false, nextScreen: false)   // repeated press at the hung app
        sys.front = 11
        let t0 = Date()
        s.doAction(.leftHalf, wholeApp: false, nextScreen: false)
        await waitUntil(3) { self.sys.setCount(2) == 1 }
        XCTAssertLessThan(Date().timeIntervalSince(t0), 0.3, "Fine's snap didn't queue behind Hung's")
    }

    func testRepeatedSnapsOnOneAppCoalesceToTheLatest() async {
        sys.addApp(10, "Slow", windows: [(1, rect(100))])
        sys.setDelay = [1: 0.2]
        sys.front = 10
        let s = make()
        s.doAction(.leftHalf, wholeApp: false, nextScreen: false)
        s.doAction(.topHalf, wholeApp: false, nextScreen: false)
        s.doAction(.rightHalf, wholeApp: false, nextScreen: false)
        await waitUntil(3) { self.sys.setCount(1) == 2 }
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(sys.setCount(1), 2, "the in-flight snap, then only the latest press")
        XCTAssertEqual(sys.frameOf(1)?.minX, 500, "ends at the right half")
    }
}
