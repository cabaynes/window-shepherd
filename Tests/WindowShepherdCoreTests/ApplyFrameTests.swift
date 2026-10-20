import XCTest
@testable import WindowShepherdCore

/// A window that, like a real app right after a move to another screen, still
/// fits sizes to the screen it was on (x ≥ 0, bottom at 1692) until it catches up.
private final class StaleScreenWindow {
    var frame: CGRect
    var staleSizes: Int          // size requests after the move still fitted to the old screen
    var resizable = true
    var pauses: [TimeInterval] = []
    init(_ f: CGRect, staleSizes: Int) { frame = f; self.staleSizes = staleSizes }

    func setSize(_ s: CGSize) {
        guard resizable else { return }
        let onOld = frame.origin.x >= 0
        var h = s.height
        if onOld || staleSizes > 0 { h = min(h, 1692 - frame.origin.y) }
        if !onOld && staleSizes > 0 { staleSizes -= 1 }
        frame.size = CGSize(width: s.width, height: h)
    }
    func apply(_ r: CGRect) -> Bool {
        applyFrame(r, setSize: setSize, setPosition: { self.frame.origin = $0; return true },
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

    func testGivesUpQuicklyWhenTheAppNeverCatchesUp() {
        let w = StaleScreenWindow(bottomOfDell, staleSizes: 99)
        XCTAssertTrue(w.apply(target))          // the move itself worked
        XCTAssertLessThanOrEqual(w.pauses.reduce(0, +), 0.15 + 1e-9)
    }

    func testAFailedMoveIsAFailureWithNoRetries() {
        let ok = applyFrame(target, setSize: { _ in }, setPosition: { _ in false }, read: { .zero },
                            canResize: { true }, pause: { _ in XCTFail("no retries after a failed move") })
        XCTAssertFalse(ok)
    }
}
