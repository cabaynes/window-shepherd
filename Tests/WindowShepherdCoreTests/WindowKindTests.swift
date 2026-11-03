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

    func testListFailureIsNotAMiss() async {
        sys.addApp(10, "Safari", windows: [(1, r)])
        sys.listBehaviour[10] = .throwAlways
        let s = make()
        for _ in 0..<5 {
            s.tick()
            await waitUntil { s.kindsInFlight.isEmpty }
        }
        XCTAssertGreaterThanOrEqual(sys.locked { sys.listCalls[10] } ?? 0, 3, "asked again on later ticks")
        XCTAssertNil(s.kinds["1"], "a failed list says nothing about the window")
    }

    func testUnreadableKindPromotedAfterThreeMisses() async {
        sys.addApp(10, "Safari", windows: [(1, r)])
        sys.unreadableKind = [1]
        let s = make()
        for _ in 0..<2 {
            s.tick()
            await waitUntil { s.kindsInFlight.isEmpty }
        }
        XCTAssertNil(s.kinds["1"])
        s.tick()
        await waitUntil { s.kinds["1"] != nil }
        XCTAssertEqual(s.kinds["1"], true)
    }

    /// A sheet: in the CoreGraphics list, not in the app's window list.
    func testSheetIsNeverAMainWindow() async {
        sys.addApp(10, "Safari", windows: [(1, r), (2, CGRect(x: 300, y: 150, width: 500, height: 300))])
        sys.hiddenFromAX = [2]
        let s = make()
        for _ in 0..<6 {
            s.tick()
            await waitUntil { s.kindsInFlight.isEmpty }
        }
        XCTAssertEqual(s.isMainWindow("1"), true)
        XCTAssertEqual(s.isMainWindow("2"), false)
    }

    /// The list has a window whose id can't be read: a missing one may be it, so it's a miss, not a dialog.
    func testMissingWhileAnIdIsUnreadableIsAMiss() async {
        sys.addApp(10, "Safari", windows: [(1, r)])
        sys.unreadableIDs = [1]
        let s = make()
        for _ in 0..<3 {
            s.tick()
            await waitUntil { s.kindsInFlight.isEmpty }
        }
        XCTAssertEqual(s.kinds["1"], true)
    }
}
