import XCTest
@testable import WindowShepherdCore

final class BackgroundShortcutsTests: XCTestCase {
    func keys(_ list: [BackgroundShortcut]) -> [String: String] {
        Dictionary(list.map { ($0.what, $0.combo.formatted) }, uniquingKeysWith: { a, _ in a })
    }

    func testRecommendedDefaults() {
        let k = keys(BackgroundShortcuts.rectangle(prefs: ["alternateDefaultShortcuts": true]))
        XCTAssertEqual(k["Previous display"], "⌃⌥⌘←")
        XCTAssertEqual(k["Next display"], "⌃⌥⌘→")
        XCTAssertEqual(k["Left half"], "⌃⌥←")
        XCTAssertFalse(k.values.contains("⌥⌘F"))
    }

    func testSpectacleWhenFlagMissing() {
        let k = keys(BackgroundShortcuts.rectangle(prefs: [:]))
        XCTAssertEqual(k["Maximize"], "⌥⌘F")
        XCTAssertEqual(k["Top left"], "⌃⌘←")
        XCTAssertEqual(k["Bottom right"], "⌃⌘→⇧")
    }

    func testCenterTwoThirdsOnlyForNewRecommendedInstalls() {
        XCTAssertEqual(keys(BackgroundShortcuts.rectangle(prefs: ["alternateDefaultShortcuts": true, "installVersion": "95"]))["Center two thirds"], "⌃⌥R")
        XCTAssertNil(keys(BackgroundShortcuts.rectangle(prefs: ["alternateDefaultShortcuts": true, "installVersion": "90"]))["Center two thirds"])
        XCTAssertNil(keys(BackgroundShortcuts.rectangle(prefs: ["installVersion": "95"]))["Center two thirds"])
    }

    func testCustomRectangleKeyOverridesDefault() {
        let list = BackgroundShortcuts.rectangle(prefs: ["alternateDefaultShortcuts": true,
                                                         "nextDisplay": ["keyCode": 5, "modifierFlags": 1572864]])
        XCTAssertEqual(keys(list)["Next display"], "⌥⌘G")
        XCTAssertFalse(list.contains { $0.combo.formatted == "⌃⌥⌘→" })
        XCTAssertEqual(list.first { $0.what == "Next display" }?.app, "Rectangle")
    }

    func testClearedRectangleActionHasNoKey() {
        let list = BackgroundShortcuts.rectangle(prefs: ["alternateDefaultShortcuts": true, "nextDisplay": [String: Any]()])
        XCTAssertNil(keys(list)["Next display"])
    }

    func testDriveDecodes() {
        XCTAssertEqual(BackgroundShortcuts.googleDrive(searchHotKey: 592705486853)?.combo.formatted, "⌥⌘G⇧")
        XCTAssertEqual(BackgroundShortcuts.googleDrive(searchHotKey: 592705486850)?.combo.formatted, "⌥⌘D⇧")
        XCTAssertEqual(BackgroundShortcuts.googleDrive(searchHotKey: 592705486853)?.what, "Search")
    }

    func testDriveZeroMeansNone() {
        XCTAssertNil(BackgroundShortcuts.googleDrive(searchHotKey: 0))
        XCTAssertNil(BackgroundShortcuts.googleDrive(searchHotKey: nil))
    }

    func testBackgroundClashText() {
        let drive = BackgroundShortcuts.googleDrive(searchHotKey: 592705486853)!
        let found = Conflicts.check(bindings: [drive.combo], sources: ClashSources(background: [drive]))
        let f = found[drive.combo.id]!.first!
        XCTAssertEqual(f.level, .warn)
        XCTAssertTrue(f.text.hasPrefix("Google Drive: Search. Both run."), f.text)
    }
}
