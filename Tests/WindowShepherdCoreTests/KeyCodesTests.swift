import XCTest
import Carbon.HIToolbox
@testable import WindowShepherdCore

final class KeyCodesTests: XCTestCase {
    func testFixedKeys() {
        XCTAssertEqual(KeyCodes.code(for: "left"), 123)
        XCTAssertEqual(KeyCodes.code(for: "right"), 124)
        XCTAssertEqual(KeyCodes.code(for: "down"), 125)
        XCTAssertEqual(KeyCodes.code(for: "up"), 126)
        XCTAssertEqual(KeyCodes.code(for: "space"), 49)
        XCTAssertEqual(KeyCodes.code(for: "tab"), 48)
        XCTAssertEqual(KeyCodes.code(for: "escape"), 53)
        XCTAssertEqual(KeyCodes.code(for: "f5"), 96)
        XCTAssertEqual(KeyCodes.name(for: 123), "left")
        XCTAssertNil(KeyCodes.code(for: "nonsense"))
    }

    func testLetterRoundTrip() throws {
        guard KeyCodes.code(for: "a") != nil else { throw XCTSkip("current keyboard layout isn't Latin") }
        for b in derive(.defaults) {
            let k = b.combo.key
            guard let code = KeyCodes.code(for: k) else { return XCTFail("no code for \(k)") }
            XCTAssertEqual(KeyCodes.name(for: UInt16(code)), k)
        }
        XCTAssertEqual(KeyCodes.code(for: "1"), 18)
    }

    /// AZERTY-style layouts type & é " ' ( … on the number row (digits need ⇧): the screen
    /// keys still bind, to the physical number-row keys.
    func testDigitsFallBackToTheNumberRow() {
        let azerty: [String: UInt32] = ["&": 18, "é": 19, "a": 12]
        let names = KeyCodes.withDigitFallbacks(azerty)
        XCTAssertEqual(names["1"], 18)
        XCTAssertEqual(names["2"], 19)
        XCTAssertEqual(names["0"], 29)
        XCTAssertEqual(names["&"], 18, "the layout's own keys stay")
        let us: [String: UInt32] = ["1": 18, "2": 19]
        XCTAssertEqual(KeyCodes.withDigitFallbacks(us)["1"], 18, "a layout that types digits keeps its own")
    }

    func testCarbonModsRoundTrip() {
        let all: Set<Mod> = [.ctrl, .alt, .cmd, .shift]
        XCTAssertEqual(carbonModifiers([.cmd]), UInt32(cmdKey))
        XCTAssertEqual(carbonModifiers([.ctrl, .alt]), UInt32(controlKey | optionKey))
        XCTAssertEqual(mods(fromCarbon: carbonModifiers(all)), all)
        XCTAssertEqual(mods(fromCGFlags: [.maskCommand, .maskShift, .maskAlphaShift]), [.cmd, .shift])
    }
}
