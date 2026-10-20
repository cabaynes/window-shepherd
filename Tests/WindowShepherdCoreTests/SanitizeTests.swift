import XCTest
@testable import WindowShepherdCore

final class SanitizeTests: XCTestCase {
    func testSanitizeBadEntries() {
        let saved: [String: Any] = [
            "actions": [
                "90%": ["key": 5],
                "Nope": ["mods": ["cmd"], "key": "x"],
                "60%": ["mods": ["alt", "cmd"], "key": "f"],
            ],
            "wholeApp": "ctrl",
        ]
        let (cfg, notes) = sanitize(saved: saved)
        let d = ShortcutConfig.defaults
        XCTAssertEqual(cfg.actions[.almost]?.id, d.actions[.almost]?.id)
        XCTAssertEqual(cfg.actions[.sixty]?.id, d.actions[.sixty]?.id)
        XCTAssertEqual(notes.count, 3, "notes: \(notes)")
        XCTAssertTrue(validate(cfg).isEmpty)
    }

    func testSanitizeUnbindableKey() {
        // a key this keyboard layout lacks can't be bound: back to the default, noted
        let saved: [String: Any] = ["actions": ["60%": ["mods": ["alt", "cmd"], "key": "§"]]]
        let (cfg, notes) = sanitize(saved: saved, isValidKey: { $0 != "§" })
        XCTAssertEqual(cfg.actions[.sixty]?.formatted, "⌥⌘H")
        XCTAssertEqual(notes.count, 1)
        let (kept, _) = sanitize(saved: saved)  // no checker: kept
        XCTAssertEqual(kept.actions[.sixty]?.key, "§")
    }

    func testSanitizeNilIsDefaults() {
        let (cfg, notes) = sanitize(saved: nil)
        XCTAssertEqual(notes.count, 0)
        XCTAssertTrue(validate(cfg).isEmpty)
        XCTAssertEqual(cfg, .defaults)
    }

    func testSanitizeRoundTrip() {
        var custom = ShortcutConfig.defaults
        custom.actions[.sixty] = Combo("u", .alt, .cmd)
        custom.menu = Combo("k", .ctrl, .alt, .cmd)
        custom.wholeApp = .shift
        custom.nextScreen = .ctrl
        let (cfg, notes) = sanitize(saved: custom.jsonObject)
        XCTAssertEqual(cfg, custom)
        XCTAssertEqual(notes, [])
    }

    func testSanitizeGarbageTypes() {
        let saved: [String: Any] = ["actions": 5, "wholeApp": "hyper", "screenBase": "x", "menu": ["key": ""]]
        let (cfg, notes) = sanitize(saved: saved)
        XCTAssertEqual(cfg, .defaults)
        XCTAssertEqual(notes.count, 3, "notes: \(notes)")
    }
}
