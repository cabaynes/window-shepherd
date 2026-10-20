import XCTest
@testable import WindowShepherdCore

final class ComboTests: XCTestCase {
    func testFormatOrder() {
        XCTAssertEqual(Combo("g", .ctrl, .alt, .cmd, .shift).formatted, "⌃⌥⌘G⇧")
        XCTAssertEqual(Combo("left", .alt, .cmd).formatted, "⌥⌘←")
    }

    func testParse() {
        XCTAssertEqual(Combo.parse("⌘⌃3⇧"), Combo("3", .ctrl, .cmd, .shift))
        XCTAssertEqual(Combo.parse("⌥⌘Space"), Combo("space", .alt, .cmd))
        XCTAssertNil(Combo.parse("⌘"))
        XCTAssertNil(Combo.parse(""))
        XCTAssertNil(Combo.parse("⇧"))  // a lone ⇧ is a modifier, not a key
    }

    func testId() {
        XCTAssertEqual(Combo("g", .shift, .cmd, .alt, .ctrl).id, "ctrl+alt+cmd+shift|g")
        XCTAssertEqual(Combo("left").id, "|left")
    }

    func testKeyLabels() {
        XCTAssertEqual(keyLabel("space"), "Space")
        XCTAssertEqual(keyLabel("down"), "↓")
        XCTAssertEqual(keyLabel("f12"), "F12")
        XCTAssertEqual(keyLabel("`"), "`")
        XCTAssertEqual(formatMods([.shift, .cmd, .ctrl]), "⌃⌘")
    }
}
