import XCTest
@testable import WindowShepherdCore

@MainActor
final class AppSpotStoreTests: XCTestCase {
    let setup = "dual"
    func entry(_ pid: Int32, _ app: String, x: Double, seen: Double) -> LayoutEntry {
        LayoutEntry(pid: pid, app: app, scr: "S1", unit: UnitRect(x: x, y: 0, w: 0.5, h: 1), seen: seen)
    }
    func bundle(_ e: LayoutEntry) -> String? { e.app == "Gone" ? nil : "b." + e.app }

    func testSeedFromLayoutsAndFrozen() {
        let layouts = [setup: ["1": entry(1, "Safari", x: 0, seen: 100), "2": entry(2, "Notes", x: 0.5, seen: 200)]]
        let frozen = [setup: FrozenCopy(layout: ["1": entry(1, "Safari", x: 0.1, seen: 50),
                                                  "3": entry(1, "Safari", x: 0.2, seen: 60)], at: 10)]
        let map = AppSpotBook.seed(layouts: layouts, frozen: frozen, bundleFor: bundle, now: 1000)
        XCTAssertEqual(map[setup]?["b.Safari"]?.count, 2)
        XCTAssertEqual(map[setup]?["b.Notes"]?.count, 1)
        XCTAssertEqual(Set(map[setup]?["b.Safari"]?.map(\.used) ?? []), [100, 60])
        XCTAssertEqual(map[setup]?["b.Notes"]?.first?.used, 200)
    }

    func testSeedDropsUnknownApps() {
        let layouts = [setup: ["1": entry(1, "Gone", x: 0, seen: 1), "2": entry(2, "Notes", x: 0, seen: 1)]]
        let map = AppSpotBook.seed(layouts: layouts, frozen: [:], bundleFor: bundle, now: 1000)
        XCTAssertNil(map[setup]?["b.Gone"])
        XCTAssertEqual(map[setup]?["b.Notes"]?.count, 1)
    }

    func testSeedKeepsMostRecentUpToCap() {
        var l: [String: LayoutEntry] = [:]
        for i in 0..<25 { l[String(i)] = entry(1, "Safari", x: 0, seen: Double(i)) }
        let map = AppSpotBook.seed(layouts: [setup: l], frozen: [:], bundleFor: bundle, now: 1000)
        let used = map[setup]?["b.Safari"]?.map(\.used).sorted() ?? []
        XCTAssertEqual(used.count, AppSpotBook.maxPerApp)
        XCTAssertEqual(used.first, 5)
    }

    // MARK: Shepherd start

    var sys: FakeWindowSystem!
    var store: LayoutStore!

    override func setUp() async throws {
        sys = FakeWindowSystem()
        sys.allScreens = [screen(1, "Built-in", x: 0, builtin: true)]
        sys.addApp(1, "Safari", windows: [])
        store = LayoutStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
    }

    func make() -> Shepherd {
        let s = Shepherd(system: sys, store: store)
        s.start()
        s.spotStore.flush()
        return s
    }

    func count(_ s: Shepherd) -> Int { s.spots.spots.values.flatMap { $0.values }.map(\.count).reduce(0, +) }

    func testStartSeedsOnceThenLoads() {
        store.save([setup: ["1": entry(1, "Safari", x: 0, seen: 5)]])
        store.flush()
        let first = make()
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.spotStore.url.path))
        XCTAssertEqual(first.spots.spots[setup]?["test.Safari"]?.count, 1)

        store.save([setup: ["1": entry(1, "Safari", x: 0, seen: 5), "2": entry(1, "Safari", x: 0.5, seen: 6)]])
        store.flush()
        let second = make()
        XCTAssertEqual(second.spots.spots, first.spots.spots)
        XCTAssertEqual(count(second), 1)
    }

    func testDamagedFileReseedsAndLogs() throws {
        store.save([setup: ["1": entry(1, "Safari", x: 0, seen: 5)]])
        store.flush()
        let url = AppSpotStore.url(beside: store.url)
        try "{".write(to: url, atomically: true, encoding: .utf8)

        let logFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".log")
        let saved = Log.fileURL
        Log.fileURL = logFile
        defer { Log.fileURL = saved }

        let s = make()
        Log.flush()
        XCTAssertEqual(s.spots.spots[setup]?["test.Safari"]?.count, 1)
        let log = try String(contentsOf: logFile, encoding: .utf8)
        XCTAssertTrue(log.contains("app spots were damaged; starting from the remembered layouts"))
        XCTAssertTrue(log.contains("app spots: seeded 1 spots for 1 apps from the remembered layouts"))
    }
}
