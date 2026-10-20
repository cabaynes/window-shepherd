import XCTest
@testable import WindowShepherdCore

final class LogTests: XCTestCase {
    func testRotatesAt256KB() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("test.log")
        let saved = Log.fileURL
        Log.fileURL = file
        defer { Log.fileURL = saved }

        Log.info(String(repeating: "x", count: 300 * 1024))
        Log.info("after rotation")
        Log.flush()

        let rotated = file.appendingPathExtension("1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rotated.path))
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as! Int
        XCTAssertLessThan(size, 1024)
    }
}

final class LogLocationTests: XCTestCase {
    func testTestsNeverWriteTheUsersLog() {
        XCTAssertFalse(Log.fileURL.path.contains("Library/Logs"), "unit tests must not write the app's real log")
    }
}
