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

    /// A saved key this keyboard lacks stays saved: written back while that shortcut is still
    /// at its default, so switching back to the layout that has the key brings it back.
    func testUnbindableSavedKeyIsKeptOnSave() throws {
        let saved: [String: Any] = ["actions": ["60%": ["mods": ["alt", "cmd"], "key": "§"],
                                                "90%": ["mods": ["alt", "cmd"], "key": "§"]]]
        let valid: (String) -> Bool = { $0 != "§" }
        let (cfg, _) = sanitize(saved: saved, isValidKey: valid)
        let held = unbindableSaved(saved: saved, isValidKey: valid)
        var edited = cfg
        edited.actions[.almost] = Combo("j", .alt, .cmd)       // you change 90% in Customize; 60% you leave
        let data = try XCTUnwrap(encodeForSave(edited, keeping: held))
        let back = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let (reloaded, _) = sanitize(saved: back)               // on a keyboard that has §
        XCTAssertEqual(reloaded.actions[.sixty]?.key, "§", "kept")
        XCTAssertEqual(reloaded.actions[.almost]?.key, "j", "your change wins")
    }

    /// Nothing customized but a held key: still saved (not "all defaults, store nothing").
    func testOnlyAHeldKeyIsStillSaved() throws {
        let saved: [String: Any] = ["menu": ["mods": ["ctrl", "alt", "cmd"], "key": "§"]]
        let held = unbindableSaved(saved: saved, isValidKey: { $0 != "§" })
        let data = try XCTUnwrap(encodeForSave(.defaults, keeping: held))
        let back = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(sanitize(saved: back).0.menu.key, "§")
        XCTAssertNil(encodeForSave(.defaults, keeping: [:]), "all defaults and nothing held: store nothing")
    }
}
