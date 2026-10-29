import XCTest
@testable import WindowShepherdCore

final class CGWindowTests: XCTestCase {
    private func row(_ id: Int, pid: Int = 10, owner: String? = "Safari", layer: Int = 0, onscreen: Bool = true,
                     w: Double = 500, h: Double = 400, title: String? = nil) -> [String: Any] {
        var d: [String: Any] = [
            kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer,
            kCGWindowIsOnscreen as String: onscreen,
            kCGWindowBounds as String: ["X": 10.0, "Y": 20.0, "Width": w, "Height": h],
        ]
        if let owner { d[kCGWindowOwnerName as String] = owner }
        if let title { d[kCGWindowName as String] = title }
        return d
    }

    func testParseFilters() {
        let list = [
            row(1, title: "Doc"),
            row(2, layer: 25),
            row(3, w: 80),
            row(4, onscreen: false),
            row(5, pid: 99),
            row(6, owner: nil),
        ]
        let out = CGWindow.parse(list, excludingPID: 99)
        XCTAssertEqual(out.map(\.id), [1, 6])
        XCTAssertEqual(out[0].title, "Doc")
        XCTAssertEqual(out[0].frame, CGRect(x: 10, y: 20, width: 500, height: 400))
        XCTAssertEqual(out[1].app, "?")
    }

    /// The lock screen after a wake is a layer-0 window too; it was being remembered and "restored".
    func testParseSkipsTheLockScreen() {
        let out = CGWindow.parse([row(1, owner: "loginwindow"), row(2)], excludingPID: nil)
        XCTAssertEqual(out.map(\.id), [2])
    }
}
