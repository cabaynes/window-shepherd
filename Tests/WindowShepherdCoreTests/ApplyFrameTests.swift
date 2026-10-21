import XCTest
@testable import WindowShepherdCore

/// A window that, like a real app right after a move to another screen, still
/// fits sizes to the screen it was on (x ≥ 0, bottom at 1692) until it catches up.
private final class StaleScreenWindow {
    var frame: CGRect
    var staleSizes: Int          // size requests after the move still fitted to the old screen
    var resizable = true
    var lagging = false          // like Chrome mid-move: reports a spot short of where it was sent
    var pauses: [TimeInterval] = []
    var positions: [CGPoint] = []
    init(_ f: CGRect, staleSizes: Int) { frame = f; self.staleSizes = staleSizes }

    func setSize(_ s: CGSize) {
        guard resizable else { return }
        let onOld = frame.origin.x >= 0
        var h = s.height
        if onOld || staleSizes > 0 { h = min(h, 1692 - frame.origin.y) }
        if !onOld && staleSizes > 0 { staleSizes -= 1 }
        frame.size = CGSize(width: s.width, height: h)
    }
    func setPosition(_ p: CGPoint) -> Bool {
        positions.append(p)
        frame.origin = lagging ? CGPoint(x: p.x + 256, y: p.y - 71) : p
        return true
    }
    func apply(_ r: CGRect) -> Bool {
        applyFrame(r, setSize: setSize, setPosition: setPosition,
                   read: { self.frame }, canResize: { self.resizable }, pause: { self.pauses.append($0) })
    }
}

final class ApplyFrameTests: XCTestCase {
    // The live failure: bottom half of the Dell → laptop, bottom stuck at the Dell's 1692.
    let target = CGRect(x: -1920, y: 587, width: 1920, height: 1206)
    let bottomOfDell = CGRect(x: 0, y: 861, width: 3008, height: 831)

    func testGrowsOnceTheAppCatchesUpWithTheNewScreen() {
        let w = StaleScreenWindow(bottomOfDell, staleSizes: 1)
        XCTAssertTrue(w.apply(target))
        XCTAssertEqual(w.frame, target)
        XCTAssertEqual(w.pauses.count, 1)
        XCTAssertEqual(w.positions.count, 1, "the position is sent once, never again")
    }

    func testAMoveThatLandsRightNeverPauses() {
        let w = StaleScreenWindow(CGRect(x: 0, y: 113, width: 2707, height: 1000), staleSizes: 0)
        XCTAssertTrue(w.apply(target))
        XCTAssertEqual(w.frame, target)
        XCTAssertEqual(w.pauses, [])
    }

    func testAWindowThatCantResizeNeverPauses() {
        let w = StaleScreenWindow(CGRect(x: 0, y: 861, width: 500, height: 400), staleSizes: 0)
        w.resizable = false
        XCTAssertTrue(w.apply(target))
        XCTAssertEqual(w.frame.origin, target.origin)
        XCTAssertEqual(w.pauses, [])
    }

    // Chrome, live 2026-10-20: re-sending a move while Chrome was still making the
    // first one left windows stuck part-way and then refusing moves between screens.
    func testAWindowStillOnItsWayIsLeftAlone() {
        let w = StaleScreenWindow(CGRect(x: -1824, y: 649, width: 1728, height: 1085), staleSizes: 0)
        w.lagging = true
        XCTAssertTrue(w.apply(CGRect(x: 150, y: 113, width: 2707, height: 1496)))
        XCTAssertEqual(w.positions.count, 1)
        XCTAssertEqual(w.pauses, [])
    }

    func testGivesUpAfterOneTryWhenTheAppNeverCatchesUp() {
        let w = StaleScreenWindow(bottomOfDell, staleSizes: 99)
        XCTAssertTrue(w.apply(target))          // the move itself worked
        XCTAssertEqual(w.pauses, [0.1])
        XCTAssertEqual(w.positions.count, 1)
    }

    func testWholePointsLikeHammerspoon() {
        let w = StaleScreenWindow(CGRect(x: 0, y: 113, width: 2707, height: 1000), staleSizes: 0)
        XCTAssertTrue(w.apply(CGRect(x: 150.4, y: 113.09, width: 2707.2, height: 1495.8)))
        XCTAssertEqual(w.positions, [CGPoint(x: 150, y: 113)])
        XCTAssertEqual(w.frame.size, CGSize(width: 2707, height: 1495))
    }

    func testAFailedMoveIsAFailureWithNoRetries() {
        let ok = applyFrame(target, setSize: { _ in }, setPosition: { _ in false }, read: { .zero },
                            canResize: { true }, pause: { _ in XCTFail("no retries after a failed move") })
        XCTAssertFalse(ok)
    }
}
