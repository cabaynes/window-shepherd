import XCTest
@testable import WindowShepherdCore

@MainActor
final class AppSpotBookTests: XCTestCase {
    let key = "K"
    let bundle = "com.example.Browser"
    let day = 86400.0

    func unit(_ x: Double, _ y: Double = 0, _ w: Double = 0.5, _ h: Double = 0.5) -> UnitRect {
        UnitRect(x: x, y: y, w: w, h: h)
    }
    func spot(_ scr: String, _ x: Double = 0) -> Spot { Spot(scr: scr, unit: unit(x)) }
    func appSpot(_ id: String, _ scr: String, _ x: Double = 0, used: Double) -> AppSpot {
        AppSpot(id: id, scr: scr, unit: unit(x), used: used)
    }
    func book(_ list: [AppSpot]) -> AppSpotBook { AppSpotBook(spots: [key: [bundle: list]]) }
    func list(_ b: AppSpotBook) -> [AppSpot] { b.spots[key]?[bundle] ?? [] }

    func testRecordAddsThenMovesHeldSpot() {
        let b = AppSpotBook(spots: [:])
        b.record(key: key, bundle: bundle, window: "1", at: spot("L", 0), now: 1)
        b.record(key: key, bundle: bundle, window: "1", at: spot("L", 0.5), now: 2)
        XCTAssertEqual(list(b).count, 1)
        XCTAssertEqual(list(b)[0].unit, unit(0.5))
        XCTAssertEqual(list(b)[0].used, 2)
        XCTAssertEqual(b.holders[key]?["1"], list(b)[0].id)
    }

    func testRecordAddsSecondSpotForSecondWindow() {
        let b = AppSpotBook(spots: [:])
        b.record(key: key, bundle: bundle, window: "1", at: spot("L"), now: 1)
        b.record(key: key, bundle: bundle, window: "2", at: spot("L"), now: 2)
        XCTAssertEqual(list(b).count, 2)
    }

    func testCapDropsLeastRecentUnheld() {
        let b = AppSpotBook(spots: [:])
        for i in 1...21 { b.record(key: key, bundle: bundle, window: "\(i)", at: spot("L", Double(i) / 100), now: Double(i)) }
        XCTAssertEqual(list(b).count, 21, "all held, so the cap waits")
        b.release(existing: [21])
        b.record(key: key, bundle: bundle, window: "22", at: spot("L", 0.9), now: 22)
        XCTAssertEqual(list(b).count, AppSpotBook.maxPerApp)
        XCTAssertFalse(list(b).contains { $0.used == 1 }, "the oldest unheld is gone")
        XCTAssertTrue(list(b).contains { $0.used == 21 })
        XCTAssertTrue(list(b).contains { $0.used == 22 })
    }

    func testAssignPrefersMostRecentForOneWindow() {
        let b = book([appSpot("a", "L", 0, used: 100), appSpot("b", "D", 0.1, used: 200)])
        let r = b.assign(key: key, bundle: bundle, windows: [(id: "1", at: spot("L", 0.25))], now: 300)
        XCTAssertEqual(r["1"]?.id, "b")
    }

    func testAssignPairsByNearnessAmongRecent() {
        let b = book([appSpot("S1", "D", 0, used: 300), appSpot("S2", "L", 0, used: 200), appSpot("S3", "L", 0, used: 100)])
        let r = b.assign(key: key, bundle: bundle,
                         windows: [(id: "lap", at: spot("L")), (id: "dell", at: spot("D"))], now: 400)
        XCTAssertEqual(r["dell"]?.id, "S1")
        XCTAssertEqual(r["lap"]?.id, "S2")
        XCTAssertEqual(Set(r.values.map(\.id)), ["S1", "S2"])
    }

    func testAssignSkipsHeldSpots() {
        let b = book([appSpot("S1", "L", 0, used: 300), appSpot("S2", "L", 0.5, used: 200)])
        b.holders[key] = ["9": "S1"]
        let r = b.assign(key: key, bundle: bundle, windows: [(id: "1", at: nil)], now: 400)
        XCTAssertEqual(r["1"]?.id, "S2")
        XCTAssertTrue(b.holds(key: key, window: "1"))
    }

    func testAssignWithMoreWindowsThanSpots() {
        let b = book([appSpot("S1", "L", 0, used: 300)])
        let r = b.assign(key: key, bundle: bundle,
                         windows: [(id: "1", at: nil), (id: "2", at: nil), (id: "3", at: nil)], now: 400)
        XCTAssertEqual(r.count, 1)
    }

    func testSpotsNeverCrossApps() {
        let b = book([appSpot("S1", "L", 0, used: 300)])
        let r = b.assign(key: key, bundle: "com.apple.Notes", windows: [(id: "1", at: nil)], now: 400)
        XCTAssertTrue(r.isEmpty)
    }

    func testHoldersArePerSetup() {
        let b = AppSpotBook(spots: [:])
        b.record(key: "A", bundle: bundle, window: "1", at: spot("L"), now: 1)
        b.record(key: "B", bundle: bundle, window: "1", at: spot("L"), now: 2)
        XCTAssertTrue(b.holds(key: "A", window: "1"))
        XCTAssertTrue(b.holds(key: "B", window: "1"))
        b.record(key: "A", bundle: bundle, window: "1", at: spot("L", 0.5), now: 3)
        XCTAssertEqual(b.spots["A"]?[bundle]?.count, 1)
        XCTAssertEqual(b.spots["B"]?[bundle]?.count, 1)
    }

    func testReleaseFreesButKeeps() {
        let b = AppSpotBook(spots: [:])
        b.record(key: key, bundle: bundle, window: "1", at: spot("L"), now: 1)
        b.release(existing: [2])
        XCTAssertEqual(list(b).count, 1)
        XCTAssertFalse(b.holds(key: key, window: "1"))
    }

    func testTouchRefreshesHeldVisible() {
        let b = AppSpotBook(spots: [:])
        b.record(key: key, bundle: bundle, window: "1", at: spot("L"), now: 1)
        b.record(key: key, bundle: bundle, window: "2", at: spot("L"), now: 1)
        b.touch(key: key, visible: ["1"], now: 50)
        XCTAssertEqual(list(b).map(\.used), [50, 1])
    }

    func testForgetOldKeepsHeld() {
        let now = 40 * day
        let b = book([appSpot("old", "L", 0, used: now - 31 * day), appSpot("heldOld", "L", 0.5, used: now - 31 * day)])
        b.holders[key] = ["1": "heldOld"]
        b.forgetOld(now: now)
        XCTAssertEqual(list(b).map(\.id), ["heldOld"])
    }

    /// An app (or a whole setup) left with no spots is dropped, not saved as an empty list.
    func testForgetOldDropsEmptyAppsAndSetups() {
        let now = 40 * day
        let b = AppSpotBook(spots: [key: [bundle: [appSpot("old", "L", 0, used: now - 31 * day)],
                                          "com.example.Kept": [appSpot("new", "L", 0, used: now)]],
                                    "K2": [bundle: [appSpot("old2", "L", 0, used: now - 31 * day)]]])
        b.forgetOld(now: now)
        XCTAssertEqual(b.spots[key]?.keys.sorted(), ["com.example.Kept"])
        XCTAssertNil(b.spots["K2"])
    }
}
