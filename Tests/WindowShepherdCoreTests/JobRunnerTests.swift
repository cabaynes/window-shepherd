import XCTest
@testable import WindowShepherdCore

@MainActor
final class JobRunnerTests: XCTestCase {
    func testRunsStepsInOrderAndInsertions() async {
        let r = JobRunner()
        var log: [String] = []
        var result: JobProblem?? = .none
        r.run(.move, steps: [
            { ctx in log.append("1"); ctx.insert({ _ in log.append("inserted"); return nil }, at: ctx.index + 1); return nil },
            { _ in log.append("2"); return nil },
        ], deadline: 5) { result = .some($0) }
        await waitUntil { result != nil }
        XCTAssertEqual(log, ["1", "inserted", "2"])
        XCTAssertEqual(result, .some(nil))
        XCTAssertNil(r.current)
    }

    func testNewJobInterruptsOld() async {
        let r = JobRunner()
        var log: [String] = []
        var oldDone: JobProblem?? = .none
        var newDone = false
        r.run(.restore, steps: [
            { _ in log.append("old1"); return 0.2 },
            { _ in log.append("old2"); return nil },
        ], deadline: 5) { p in oldDone = .some(p); log.append("oldDone") }
        await waitUntil { log.contains("old1") }
        r.run(.move, steps: [{ _ in log.append("new1"); return nil }], deadline: 5) { _ in newDone = true }
        await waitUntil { newDone }
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(oldDone, .some(.interrupted))
        XCTAssertEqual(log, ["old1", "oldDone", "new1"])
    }

    func testOutOfTime() async {
        let r = JobRunner()
        var result: JobProblem?? = .none
        let step: JobStep = { _ in 0.03 }
        r.run(.move, steps: Array(repeating: step, count: 10), deadline: 0.05) { result = .some($0) }
        await waitUntil { result != nil }
        XCTAssertEqual(result, .some(.outOfTime))
    }

    func testWaitIsHonoured() async {
        let r = JobRunner()
        var t1 = Date.distantPast, t2 = Date.distantPast
        var done = false
        r.run(.move, steps: [{ _ in t1 = Date(); return 0.2 }, { _ in t2 = Date(); return nil }], deadline: 5) { _ in done = true }
        await waitUntil { done }
        XCTAssertGreaterThanOrEqual(t2.timeIntervalSince(t1), 0.19)
    }

    func testStopSilently() async {
        let r = JobRunner()
        var called = false
        var ran2 = false
        r.run(.move, steps: [{ _ in 0.1 }, { _ in ran2 = true; return nil }], deadline: 5) { _ in called = true }
        XCTAssertNotNil(r.current)
        r.stopCurrent(reportAs: nil)
        XCTAssertNil(r.current)
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertFalse(called)
        XCTAssertFalse(ran2)
    }

    func testClearIfStale() {
        let r = JobRunner()
        r.run(.move, steps: [{ _ in 10 }], deadline: 1) { _ in }
        r.clearIfStale(now: Date().addingTimeInterval(3))
        XCTAssertNotNil(r.current, "within deadline + 5 s")
        r.clearIfStale(now: Date().addingTimeInterval(7))
        XCTAssertNil(r.current)
    }

    func testBusyCallback() async {
        let r = JobRunner()
        var changes = 0
        r.onBusyChanged = { changes += 1 }
        var done = false
        r.run(.move, steps: [{ _ in nil }], deadline: 5) { _ in done = true }
        await waitUntil { done }
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(changes, 2)
    }

    func testDeadlineFormula() {
        XCTAssertEqual(deadlineFor(windowCount: 0), 10)
        XCTAssertEqual(deadlineFor(windowCount: 50), 60)
        XCTAssertEqual(deadlineFor(windowCount: 500), 120)
    }
}
