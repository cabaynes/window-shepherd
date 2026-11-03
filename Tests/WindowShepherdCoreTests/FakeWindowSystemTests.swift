import XCTest
@testable import WindowShepherdCore

final class FakeWindowSystemTests: XCTestCase {
    func testFakeReportsBundleLaunchKindAndFixedSize() throws {
        let sys = FakeWindowSystem()
        let r = CGRect(x: 0, y: 0, width: 400, height: 300)
        sys.addApp(10, "Safari", windows: [(1, r)], bundle: "com.apple.Safari")
        let d = Date(timeIntervalSince1970: 1_000)
        sys.launched[10] = d
        sys.nonStandard = [1]
        sys.fixedSize = [1]
        XCTAssertEqual(sys.bundleID(pid: 10), "com.apple.Safari")
        XCTAssertEqual(sys.launchDate(pid: 10), d)
        let w = try XCTUnwrap(sys.appWindows(pid: 10).first)
        XCTAssertEqual(w.isStandard, false)
        XCTAssertFalse(w.isResizable)
        try w.setFrame(CGRect(x: 500, y: 0, width: 900, height: 900))
        XCTAssertEqual(sys.frameOf(1), CGRect(x: 500, y: 0, width: 400, height: 300))
    }
}
