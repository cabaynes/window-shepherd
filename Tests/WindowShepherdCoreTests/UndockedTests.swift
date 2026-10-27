import XCTest
@testable import WindowShepherdCore

@MainActor
final class UndockedTests: XCTestCase {
    var sys: FakeWindowSystem!
    var store: LayoutStore!
    let lap = screen(1, "Built-in", x: 0, builtin: true)
    let dell = screen(2, "DELL", x: 1000, w: 2560, h: 1440)

    override func setUp() async throws {
        sys = FakeWindowSystem()
        sys.allScreens = [lap, dell]
        sys.main = lap
        store = LayoutStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
    }

    func make() -> Shepherd {
        let s = Shepherd(system: sys, store: store, timing: MoveTiming(retryWaits: [0.05, 0.1], movePatience: 0.3),
                         restoreTiming: RestoreTiming(passes: [0.05, 0.15, 0.3], busyRecheck: 0.05, unsettledLimit: 1, patience: 0.3))
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

    /// Docked with Safari remembered on the Dell; unplug; open Notes window 7 on the built-in screen.
    func openedWhileUndocked(_ configure: (Shepherd) -> Void = { _ in }) async -> Shepherd {
        sys.addApp(10, "Safari", windows: [(1, rect(1100))])
        let s = make()
        configure(s)
        s.tick()
        sys.allScreens = [lap]
        move(1, to: rect(50))
        s.screensChanged()
        await waitUntil { !s.isBusy }
        sys.addApp(30, "Notes", windows: [(7, rect(40))])
        s.tick(); s.tick()
        sys.allScreens = [lap, dell]
        s.tick()
        await waitUntil(4) { !s.isBusy }
        return s
    }

    func testBiggestScreen() {
        XCTAssertEqual(Screens.biggest([lap, dell])?.uuid, dell.uuid)
        XCTAssertEqual(Screens.biggest([lap])?.uuid, lap.uuid)
    }

    func testNamedScreenUsedWhenConnected() {
        let u = UndockedWindows(enabled: true, target: .named(uuid: lap.uuid, name: "Built-in"), size: .ninety)
        XCTAssertEqual(u.screen(in: [lap, dell])?.uuid, lap.uuid)
    }

    func testNamedScreenMissingFallsBackToBiggest() {
        let u = UndockedWindows(enabled: true, target: .named(uuid: "GONE", name: "LG"), size: .ninety)
        XCTAssertEqual(u.screen(in: [lap, dell])?.uuid, dell.uuid)
    }

    func testDefaultsAreOnBiggest90() {
        XCTAssertEqual(UndockedWindows.defaults, UndockedWindows(enabled: true, target: .biggest, size: .ninety))
    }

    func testWindowOpenedWhileUndockedGoesToBiggestAt90() async {
        _ = await openedWhileUndocked()
        XCTAssertEqual(sys.frameOf(7), Geometry.place(UnitRect(x: 0.05, y: 0.05, w: 0.9, h: 0.9), in: dell.frame))
        XCTAssertEqual(sys.frameOf(1)?.minX ?? 0, 1100, accuracy: 0.5, "remembered windows still go home")
    }

    func testUndockedOffLeavesThem() async {
        _ = await openedWhileUndocked { $0.undocked.enabled = false }
        XCTAssertEqual(sys.frameOf(7), rect(40))
        XCTAssertEqual(sys.setCount(7), 0)
    }

    func testKeepSizeCenters() async {
        _ = await openedWhileUndocked { $0.undocked.size = .keep }
        XCTAssertEqual(sys.frameOf(7), Geometry.centered(CGSize(width: 400, height: 300), in: dell.frame))
    }

    func testKeepSizeWithUnreadableFrameDoesNotShrink() async {
        _ = await openedWhileUndocked { s in
            s.undocked.size = .keep
            self.sys.noFrame = [7]
        }
        XCTAssertEqual(sys.frameOf(7), rect(40))
    }

    func testOnlyWhenAScreenIsAdded() async {
        sys.addApp(10, "Safari", windows: [(1, rect(1100))])
        let s = make()
        s.tick()
        sys.addApp(30, "Notes", windows: [(8, rect(1500))])   // opened while docked
        s.tick(); s.tick()
        sys.allScreens = [lap]
        move(1, to: rect(50)); move(8, to: rect(60))
        s.screensChanged()                                     // unplugging adds no screen
        await waitUntil(4) { !s.isBusy }
        XCTAssertEqual(sys.setCount(8), 0, "never moved by the undocked rule")
    }
}
