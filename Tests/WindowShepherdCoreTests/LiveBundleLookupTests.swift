import XCTest
@testable import WindowShepherdCore

/// The one-time seed finds an app's bundle ID by name, running or only installed.
@MainActor
final class LiveBundleLookupTests: XCTestCase {
    func testInstalledAppIsFoundByName() {
        let sys = LiveWindowSystem()
        XCTAssertEqual(sys.bundleID(appName: "Calculator"), "com.apple.calculator")   // /System/Applications
        XCTAssertEqual(sys.bundleID(appName: "Activity Monitor"), "com.apple.ActivityMonitor")   // …/Utilities
        XCTAssertNil(sys.bundleID(appName: "No Such App 7f3c"))
    }
}
