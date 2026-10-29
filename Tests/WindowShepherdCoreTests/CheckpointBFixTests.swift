import XCTest
@testable import WindowShepherdCore

@MainActor
final class CheckpointBFixTests: XCTestCase {
    func testRetryRunsOnlyTheOfferTheMenuShowed() async {
        let sys = FakeWindowSystem()
        sys.addApp(10, "Safari", windows: [(1, CGRect(x: 100, y: 125, width: 400, height: 300))])
        sys.listBehaviour[10] = .throwAlways
        let store = LayoutStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
        var alerts: [String] = []
        let s = Shepherd(system: sys, store: store, timing: MoveTiming(retryWaits: [0.01, 0.02], movePatience: 0.1))
        s.onAlert = { alerts.append($0) }
        s.start()
        s.apply(.everything, placer: .fraction(1, on: .own), label: "Full screen")
        await waitUntil { alerts.count == 1 }
        let shown = s.retryOffer!.at
        // A newer offer replaces it while the menu is open…
        s.apply(.everything, placer: .fraction(0.9, on: .own), label: "90%")
        await waitUntil { alerts.count == 2 }
        XCTAssertNotEqual(s.retryOffer!.at, shown)
        // …so the stale row does nothing.
        sys.listBehaviour[10] = .ok
        s.runRetry(offerAt: shown)
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(sys.setCount(1), 0)
        XCTAssertEqual(MenuModel.build(MenuInputs(ctx: MenuContext(), screens: [], bindings: [], config: .defaults,
                                                  retry: (count: 1, titles: ["x"]), launchAtLogin: false, retryAt: shown)).first,
                       .item(title: "Retry 1 window that didn't move", keys: nil, action: .retry(at: shown)))
    }
}
