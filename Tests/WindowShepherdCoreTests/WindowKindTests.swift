import XCTest
@testable import WindowShepherdCore

@MainActor
final class WindowKindTests: XCTestCase {
    var sys: FakeWindowSystem!

    override func setUp() async throws {
        sys = FakeWindowSystem()
        let lap = screen(1, "Built-in", x: 0, builtin: true)
        sys.allScreens = [lap]
        sys.main = lap
    }

    func make() -> Shepherd {
        let store = LayoutStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
        let s = Shepherd(system: sys, store: store, timing: MoveTiming(retryWaits: [0.05]),
                         restoreTiming: RestoreTiming(passes: [0.05], busyRecheck: 0.05, unsettledLimit: 1, patience: 0.5))
        s.start()
        return s
    }

    let r = CGRect(x: 100, y: 125, width: 400, height: 300)

    func testKindsLearnedForNewWindows() async {
        sys.addApp(10, "Safari", windows: [(1, r), (2, r)])
        sys.nonStandard = [2]
        let s = make()
        s.tick()
        await waitUntil { s.kinds.count == 2 }
        XCTAssertEqual(s.kinds, ["1": true, "2": false])
        XCTAssertEqual(s.isMainWindow("2"), false)
        XCTAssertNil(s.isMainWindow("9"))
    }

    func testKindsAskedOncePerWindow() async {
        sys.addApp(10, "Safari", windows: [(1, r), (2, r)])
        let s = make()
        s.tick()
        await waitUntil { s.kinds.count == 2 }
        s.tick(); s.tick()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(sys.locked { sys.listCalls[10] }, 1)
    }

    func testSlowAppDoesNotDelayTick() {
        sys.addApp(10, "Safari", windows: [(1, r)])
        sys.listBehaviour[10] = .sleep(1)
        let s = make()
        let t0 = Date()
        s.tick()
        XCTAssertLessThan(Date().timeIntervalSince(t0), 0.1)
        XCTAssertNil(s.isMainWindow("1"))
    }

    func testClosedWindowsAreForgotten() async {
        sys.addApp(10, "Safari", windows: [(1, r), (2, r)])
        let s = make()
        s.tick()
        await waitUntil { s.kinds.count == 2 }
        sys.locked { sys.windows.removeAll { $0.id == 2 } }
        s.forgetKinds()
        XCTAssertEqual(s.kinds, ["1": true])
    }
}
