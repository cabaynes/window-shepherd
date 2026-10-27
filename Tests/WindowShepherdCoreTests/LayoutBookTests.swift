import XCTest
@testable import WindowShepherdCore

@MainActor
final class LayoutBookTests: XCTestCase {
    let lap = screen(1, "Built-in", x: 0, builtin: true)
    let dell = screen(2, "DELL", x: 1000)
    let key = "K"
    let day = 86400.0

    func win(_ id: UInt32, x: CGFloat, pid: pid_t = 10, app: String = "Safari") -> CGWindow {
        CGWindow(id: id, pid: pid, app: app, title: nil, frame: CGRect(x: x, y: 125, width: 400, height: 300))
    }

    func book() -> LayoutBook {
        let b = LayoutBook(layouts: [:])
        b.setupChanged(to: key, now: 0)
        b.settled = true
        return b
    }

    func testForgetClosedDropsOnlyClosedWindowsOfRunningApps() {
        let b = book()
        let u = UnitRect(x: 0, y: 0, w: 1, h: 1)
        b.layouts[key] = ["1": LayoutEntry(pid: 10, app: "Chrome", scr: "UUID-2", unit: u, seen: 0),   // closed
                          "2": LayoutEntry(pid: 10, app: "Chrome", scr: "UUID-2", unit: u, seen: 0),   // other Space: exists
                          "3": LayoutEntry(pid: 30, app: "Quit", scr: "UUID-2", unit: u, seen: 0)]     // app not running: restorePlan's job
        XCTAssertTrue(b.forgetClosed(existing: [2], running: [10]))
        XCTAssertEqual(Set(b.layouts[key]!.keys), ["2", "3"])
        XCTAssertFalse(b.forgetClosed(existing: [2], running: [10]), "nothing more to drop")
    }

    func testRecordsOnlyAfterTwoSightings() {
        let b = book()
        XCTAssertFalse(b.snapshot(key: key, windows: [win(1, x: 1100)], screens: [lap, dell], now: 1))
        XCTAssertNil(b.layouts[key]?["1"])
        XCTAssertTrue(b.snapshot(key: key, windows: [win(1, x: 1100)], screens: [lap, dell], now: 3))
        XCTAssertEqual(b.layouts[key]?["1"]?.scr, "UUID-2")
        XCTAssertFalse(b.snapshot(key: key, windows: [win(1, x: 1100)], screens: [lap, dell], now: 5), "unchanged")
    }

    func testMidUnplugSightingDoesNotOverwrite() {
        let b = book()
        b.snapshot(key: key, windows: [win(1, x: 1100)], screens: [lap, dell], now: 1)
        b.snapshot(key: key, windows: [win(1, x: 1100)], screens: [lap, dell], now: 3)
        let before = b.layouts[key]?["1"]
        b.snapshot(key: key, windows: [win(1, x: 100)], screens: [lap, dell], now: 5)   // shoved once
        XCTAssertEqual(b.layouts[key]?["1"]?.scr, before?.scr)
        XCTAssertEqual(b.layouts[key]?["1"]?.unit, before?.unit)
    }

    func testUnseenWindowsKeptUntilThirtyDays() {
        let b = book()
        b.snapshot(key: key, windows: [win(1, x: 1100)], screens: [lap, dell], now: 1)
        b.snapshot(key: key, windows: [win(1, x: 1100)], screens: [lap, dell], now: 3)
        // window 1 is minimized / on another Space: absent from the list from now on
        b.snapshot(key: key, windows: [], screens: [lap, dell], now: 29 * day)
        XCTAssertNotNil(b.layouts[key]?["1"], "kept at 29 days")
        XCTAssertTrue(b.snapshot(key: key, windows: [], screens: [lap, dell], now: 31 * day))
        XCTAssertNil(b.layouts[key]?["1"], "forgotten at 31 days")
    }

    func testProtectBlocksRecordingUntilUserMovesIt() {
        let b = book()
        let dumped = Geometry.whereIs(win(1, x: 100).frame, in: [lap, dell])!
        b.protect["1"] = dumped
        b.snapshot(key: key, windows: [win(1, x: 100)], screens: [lap, dell], now: 1)
        b.snapshot(key: key, windows: [win(1, x: 100)], screens: [lap, dell], now: 3)
        XCTAssertNil(b.layouts[key]?["1"], "the dumped spot isn't recorded")
        b.snapshot(key: key, windows: [win(1, x: 300)], screens: [lap, dell], now: 5)   // you moved it
        XCTAssertNil(b.protect["1"])
        XCTAssertTrue(b.restoredIds.contains("1"), "yours now: restore leaves it")
        b.snapshot(key: key, windows: [win(1, x: 300)], screens: [lap, dell], now: 7)
        XCTAssertNotNil(b.layouts[key]?["1"])
    }

    func testRecordNowSkipsTwoSightingsAndClearsProtect() {
        let b = book()
        b.protect["1"] = Spot(scr: "UUID-1", unit: UnitRect(x: 0, y: 0, w: 1, h: 1))
        b.recordNow(ids: ["1"], key: key, windows: [win(1, x: 1100), win(2, x: 1200)], screens: [lap, dell], now: 1)
        XCTAssertEqual(b.layouts[key]?["1"]?.scr, "UUID-2")
        XCTAssertNil(b.layouts[key]?["2"], "only the windows that moved")
        XCTAssertNil(b.protect["1"])
        b.recordNow(ids: ["2"], key: "OTHER", windows: [win(2, x: 1200)], screens: [lap, dell], now: 1)
        XCTAssertNil(b.layouts["OTHER"], "setup changed: nothing recorded")
    }

    func testRestorePlanSkipsInPlaceAndRestored() {
        let b = book()
        let home = Geometry.whereIs(win(1, x: 1100).frame, in: [lap, dell])!
        b.layouts[key] = [
            "1": LayoutEntry(pid: 10, app: "Safari", scr: home.scr, unit: home.unit, seen: 0),   // dumped on laptop now
            "2": LayoutEntry(pid: 10, app: "Safari", scr: home.scr, unit: home.unit, seen: 0),   // already home
            "3": LayoutEntry(pid: 10, app: "Safari", scr: home.scr, unit: home.unit, seen: 0),   // restored earlier
            "4": LayoutEntry(pid: 10, app: "Safari", scr: "GONE", unit: home.unit, seen: 0),     // screen not here
        ]
        b.restoredIds = ["3"]
        let plan = b.restorePlan(key: key, windows: [win(1, x: 100), win(2, x: 1100), win(3, x: 100)],
                                 screens: [lap, dell], running: [10])!
        XCTAssertEqual(Set(plan[10]?.keys ?? [:].keys), [1])
        XCTAssertEqual(plan[10]?[1]?.screenUUID, "UUID-2")
        XCTAssertEqual(plan[10]?[1]?.from?.scr, "UUID-1")
        XCTAssertTrue(b.restoredIds.contains("2"), "in place: a later pass won't move it if you drag it")
        XCTAssertEqual(b.planCounts, PlanCounts(remembered: 4, toMove: 1, inPlace: 1, doneEarlier: 1, screenGone: 1))
        XCTAssertNil(b.restorePlan(key: "NOPE", windows: [], screens: [lap], running: []))
    }

    func testRestorePlanDropsQuitApps() {
        let b = book()
        b.layouts[key] = ["1": LayoutEntry(pid: 77, app: "Gone", scr: "UUID-2", unit: UnitRect(x: 0, y: 0, w: 1, h: 1), seen: 0)]
        let plan = b.restorePlan(key: key, windows: [], screens: [lap, dell], running: [10])
        XCTAssertEqual(plan?.isEmpty, true)
        XCTAssertNil(b.layouts[key]?["1"])
    }

    func testRestoreFinishedProtectsUnmoved() {
        let b = book()
        let from = Spot(scr: "UUID-1", unit: UnitRect(x: 0.1, y: 0.1, w: 0.4, h: 0.4))
        let plan: [pid_t: [UInt32: RestoreTarget]] = [10: [
            1: RestoreTarget(id: "1", screenUUID: "UUID-2", unit: from.unit, from: from),
            2: RestoreTarget(id: "2", screenUUID: "UUID-2", unit: from.unit, from: from),
            3: RestoreTarget(id: "3", screenUUID: "UUID-2", unit: from.unit, from: nil),
        ]]
        b.restoredIds = ["2"]
        b.restoreFinished(plan: plan)
        XCTAssertEqual(b.protect["1"], from)
        XCTAssertNil(b.protect["2"])
        XCTAssertNil(b.protect["3"])
    }

    func testPrune() {
        let b = LayoutBook(layouts: [key: [
            "1": LayoutEntry(pid: 10, app: "Safari", scr: "A", unit: UnitRect(x: 0, y: 0, w: 1, h: 1), seen: 0),
            "2": LayoutEntry(pid: 11, app: "Mail", scr: "A", unit: UnitRect(x: 0, y: 0, w: 1, h: 1), seen: 0),
            "3": LayoutEntry(pid: 12, app: "Notes", scr: "A", unit: UnitRect(x: 0, y: 0, w: 1, h: 1), seen: 0),
        ]])
        b.prune(running: [10: "Safari", 11: "Calendar"])   // pid 11 reused by another app, 12 gone
        XCTAssertEqual(Set(b.layouts[key]!.keys), ["1"])
    }

    func testSetupChangedResets() {
        let b = book()
        b.restoredIds = ["1"]; b.protect["1"] = Spot(scr: "A", unit: UnitRect(x: 0, y: 0, w: 1, h: 1))
        b.setupChanged(to: "NEW", now: 42)
        XCTAssertEqual(b.lastSetup, "NEW")
        XCTAssertFalse(b.settled)
        XCTAssertEqual(b.changedAt, 42)
        XCTAssertTrue(b.restoredIds.isEmpty)
        XCTAssertTrue(b.protect.isEmpty)
    }

    func testStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "/layouts.json")
        let store = LayoutStore(url: url)
        XCTAssertTrue(store.load().isEmpty, "missing file → empty")
        let layouts = [key: ["1": LayoutEntry(pid: 10, app: "Safari", scr: "A", unit: UnitRect(x: 0.1, y: 0.2, w: 0.3, h: 0.4), seen: 5)]]
        store.save(layouts)
        store.flush()
        XCTAssertEqual(LayoutStore(url: url).load(), layouts)
    }

    func testCorruptLayoutsFileStartsEmpty() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try "{nope".write(to: url, atomically: true, encoding: .utf8)
        let store = LayoutStore(url: url)
        XCTAssertTrue(store.load().isEmpty)
        let layouts = [key: ["1": LayoutEntry(pid: 1, app: "A", scr: "B", unit: UnitRect(x: 0, y: 0, w: 1, h: 1), seen: 0)]]
        store.save(layouts)
        store.flush()
        XCTAssertEqual(store.load(), layouts)
    }
}
