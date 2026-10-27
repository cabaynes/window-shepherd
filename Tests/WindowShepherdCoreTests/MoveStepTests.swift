import XCTest
@testable import WindowShepherdCore

@MainActor
final class MoveStepTests: XCTestCase {
    let timing = MoveTiming(windowLimit: 0.8, listSlow: 0.4, retryWaits: [0.05, 0.1])
    let worker = AXWorker(label: "test")
    let target = CGRect(x: 1, y: 2, width: 300, height: 200)

    private func run(_ sys: FakeWindowSystem, pid: pid_t, wanted: [UInt32: Bool]) async -> (Tally<Bool>, JobProblem?) {
        let tally = Tally<Bool>()
        let runner = JobRunner()
        var result: JobProblem?? = .none
        let step = appStep(pid: pid, wanted: wanted, system: sys, worker: worker, timing: timing, tally: tally,
                           action: { win, _ in try win.setFrame(self.target) })
        runner.run(.move, steps: [step], deadline: 10) { result = .some($0) }
        await waitUntil(5) { result != nil }
        tally.settle()
        return (tally, result ?? nil)
    }

    func testMovesOnlyWantedWindows() async {
        let sys = FakeWindowSystem()
        sys.addApp(10, "Fake", windows: [(1, .zero), (2, .zero), (3, .zero)])
        let (tally, problem) = await run(sys, pid: 10, wanted: [1: true, 3: true])
        XCTAssertNil(problem)
        XCTAssertEqual(tally.moved, 2)
        XCTAssertEqual(tally.ids, ["1", "3"])
        XCTAssertEqual(sys.setCount(2), 0)
        XCTAssertEqual(sys.frameOf(1), target)
    }

    func testLogsWhyWantedWindowsDidNotMove() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".log")
        let saved = Log.fileURL
        Log.fileURL = file
        defer { Log.fileURL = saved }
        let sys = FakeWindowSystem()
        sys.addApp(10, "Fake", windows: [(1, .zero), (2, .zero)])
        sys.failSet = [2]
        let (tally, _) = await run(sys, pid: 10, wanted: [1: true, 2: true, 3: true])   // 3 isn't in its list
        XCTAssertEqual(tally.moved, 1)
        Log.flush()
        let log = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(log.contains("Fake: 3 to move, 2 in its window list, 1 moved, 1 refused (AX -25200)"), log)
    }

    func testSilentWhenEverythingMoved() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".log")
        let saved = Log.fileURL
        Log.fileURL = file
        defer { Log.fileURL = saved }
        let sys = FakeWindowSystem()
        sys.addApp(10, "Fake", windows: [(1, .zero)])
        _ = await run(sys, pid: 10, wanted: [1: true])
        Log.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testSlowListRetriesThenSkips() async {
        let sys = FakeWindowSystem()
        sys.addApp(10, "Fake", windows: [(1, .zero), (2, .zero)])
        sys.listBehaviour[10] = .throwAlways
        let (tally, _) = await run(sys, pid: 10, wanted: [1: true, 2: true])
        XCTAssertEqual(tally.skipped, ["Fake"])
        XCTAssertEqual(Set(tally.missed[10]?.keys ?? [:].keys), [1, 2])
        XCTAssertEqual(sys.listCalls[10], 3)
        XCTAssertEqual(tally.moved, 0)
    }

    func testRecoversOnSecondTry() async {
        let sys = FakeWindowSystem()
        sys.addApp(10, "Fake", windows: [(1, .zero), (2, .zero)])
        sys.listBehaviour[10] = .throwTimes(1)
        let (tally, _) = await run(sys, pid: 10, wanted: [1: true, 2: true])
        XCTAssertEqual(tally.moved, 2)
        XCTAssertEqual(tally.skipped, [])
        XCTAssertTrue(tally.missed.isEmpty)
    }

    func testSlowWindowPartly() async {
        let sys = FakeWindowSystem()
        sys.addApp(10, "Fake", windows: [(1, .zero), (2, .zero)])
        sys.setDelay[2] = 0.9      // slow and failing on every try (a slow success counts as moved)
        sys.failSet = [2]
        let (tally, _) = await run(sys, pid: 10, wanted: [1: true, 2: true])
        XCTAssertEqual(tally.skipped, ["Fake, partly"])
        XCTAssertEqual(Array(tally.missed[10]?.keys ?? [:].keys), [2])
        XCTAssertEqual(sys.frameOf(1), target)
    }

    func testEmptySlowListCountsAsNotResponding() async {
        let sys = FakeWindowSystem()
        sys.apps[10] = "Fake"   // no windows in its AX list
        sys.listBehaviour[10] = .sleep(0.45)
        let (tally, _) = await run(sys, pid: 10, wanted: [7: true])
        XCTAssertEqual(tally.skipped, ["Fake"])
    }

    func testQuitAppIsIgnored() async {
        let sys = FakeWindowSystem()
        let (tally, problem) = await run(sys, pid: 99, wanted: [1: true])
        XCTAssertNil(problem)
        XCTAssertEqual(tally.skipped, [])
        XCTAssertEqual(tally.moved, 0)
    }

    func testReportText() {
        XCTAssertEqual(reportText("Moved 3 windows → 90%", skipped: ["Safari"], hasMissed: true, problem: .interrupted),
                       "Moved 3 windows → 90%\n(skipped, not responding: Safari)\nRetry from the ⧉ menu\n(interrupted by a newer move)")
        XCTAssertEqual(reportText("Moved 1 window → Laptop (full)", skipped: [], hasMissed: false, problem: .outOfTime),
                       "Moved 1 window → Laptop (full)\n(stopped: took too long)")
        XCTAssertEqual(reportText("x", skipped: [], hasMissed: false, problem: nil), "x")
    }
}
