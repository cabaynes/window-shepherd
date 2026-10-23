import Foundation

/// A shortcut another app catches in the background (not from a menu), so the
/// menu scan can't see it. `effect` says what happens when both apps have it.
public struct BackgroundShortcut: Equatable {
    public let combo: Combo
    public let app: String
    public let what: String
    public let effect: String
    public init(combo: Combo, app: String, what: String, effect: String) {
        self.combo = combo; self.app = app; self.what = what; self.effect = effect
    }
}

/// Reads Rectangle's and Google Drive's global shortcuts from their saved
/// preferences: a local file read, never a call to the app.
public enum BackgroundShortcuts {
    public static let rectangleID = "com.knollsoft.Rectangle"
    static let driveSettingsID = "com.google.drivefs.settings"

    /// Rectangle's shortcuts while it runs, then Google Drive's search key.
    public static func live(rectangleRunning: Bool) -> [BackgroundShortcut] {
        var list = rectangleRunning ? rectangleLive() : []
        let drive = CFPreferencesCopyAppValue("SearchHotKey" as CFString, driveSettingsID as CFString) as? NSNumber
        if let d = googleDrive(searchHotKey: drive?.int64Value) { list.append(d) }
        return list
    }

    // MARK: Rectangle

    /// Rectangle's shortcuts from its saved preferences (whether or not it runs).
    public static func rectangleLive() -> [BackgroundShortcut] {
        let prefs = CFPreferencesCopyMultiple(nil, rectangleID as CFString, kCFPreferencesCurrentUser,
                                              kCFPreferencesAnyHost) as? [String: Any]
        return rectangle(prefs: prefs ?? [:])
    }

    private typealias Default = (action: String, code: UInt16, mods: Set<Mod>)

    // Rectangle's two default sets, copied as data from rxhanson/Rectangle
    // (MIT), Rectangle/WindowAction.swift: spectacleDefault and alternateDefault.
    private static let spectacle: [Default] = [
        ("leftHalf", 123, [.cmd, .alt]), ("rightHalf", 124, [.cmd, .alt]), ("maximize", 3, [.cmd, .alt]),
        ("maximizeHeight", 126, [.ctrl, .alt, .shift]), ("previousDisplay", 123, [.ctrl, .alt, .cmd]),
        ("nextDisplay", 124, [.ctrl, .alt, .cmd]), ("larger", 124, [.ctrl, .alt, .shift]),
        ("smaller", 123, [.ctrl, .alt, .shift]), ("bottomHalf", 125, [.cmd, .alt]), ("topHalf", 126, [.cmd, .alt]),
        ("center", 8, [.alt, .cmd]), ("bottomLeft", 123, [.cmd, .ctrl, .shift]),
        ("bottomRight", 124, [.cmd, .ctrl, .shift]), ("topLeft", 123, [.ctrl, .cmd]), ("topRight", 124, [.ctrl, .cmd]),
        ("restore", 51, [.ctrl, .alt]),
    ]
    private static let recommended: [Default] = [
        ("leftHalf", 123, [.ctrl, .alt]), ("rightHalf", 124, [.ctrl, .alt]), ("bottomHalf", 125, [.ctrl, .alt]),
        ("topHalf", 126, [.ctrl, .alt]), ("bottomLeft", 38, [.ctrl, .alt]), ("bottomRight", 40, [.ctrl, .alt]),
        ("topLeft", 32, [.ctrl, .alt]), ("topRight", 34, [.ctrl, .alt]), ("maximize", 36, [.ctrl, .alt]),
        ("maximizeHeight", 126, [.ctrl, .alt, .shift]), ("previousDisplay", 123, [.ctrl, .alt, .cmd]),
        ("nextDisplay", 124, [.ctrl, .alt, .cmd]), ("larger", 24, [.ctrl, .alt]), ("smaller", 27, [.ctrl, .alt]),
        ("center", 8, [.ctrl, .alt]), ("restore", 51, [.ctrl, .alt]), ("firstThird", 2, [.ctrl, .alt]),
        ("firstTwoThirds", 14, [.ctrl, .alt]), ("centerThird", 3, [.ctrl, .alt]), ("lastTwoThirds", 17, [.ctrl, .alt]),
        ("lastThird", 5, [.ctrl, .alt]),
    ]

    /// Rectangle's active shortcuts: the chosen default set ("Recommended" when
    /// alternateDefaultShortcuts is on, else Spectacle), then the user's own
    /// keys on top; an empty entry means the user cleared that one.
    public static func rectangle(prefs: [String: Any]) -> [BackgroundShortcut] {
        let isRecommended = prefs["alternateDefaultShortcuts"] as? Bool ?? false
        var defaults = isRecommended ? recommended : spectacle
        let installVersion = (prefs["installVersion"] as? String).flatMap { Int($0) } ?? (prefs["installVersion"] as? NSNumber)?.intValue
        if isRecommended, (installVersion ?? 0) > 94 {
            defaults.append(("centerTwoThirds", 15, [.ctrl, .alt]))   // Rectangle adds it for installs after 94
        }
        var keys: [String: Combo] = [:]
        for d in defaults {
            if let name = KeyCodes.name(for: d.code) { keys[d.action] = Combo(mods: d.mods, key: name) }
        }
        for (action, value) in prefs {
            guard let dict = value as? [String: Any] else { continue }
            if dict.isEmpty { keys[action] = nil; continue }
            guard let code = (dict["keyCode"] as? NSNumber)?.uint16Value,
                  let flags = (dict["modifierFlags"] as? NSNumber)?.intValue,
                  let combo = Conflicts.fromSymbolic(keyName: KeyCodes.name(for: code), flags: flags) else { continue }
            keys[action] = combo
        }
        return keys.sorted { $0.key < $1.key }.map {
            BackgroundShortcut(combo: $0.value, app: "Rectangle", what: humanized($0.key),
                               effect: "Rectangle gets it while it's running.")
        }
    }

    /// "previousDisplay" → "Previous display".
    static func humanized(_ action: String) -> String {
        var out = ""
        for ch in action {
            if ch.isUppercase { out += " " + ch.lowercased() } else { out.append(ch) }
        }
        return out.prefix(1).uppercased() + out.dropFirst()
    }

    // MARK: Google Drive

    /// Drive's search key: the low 32 bits are the key code, the high bits
    /// its own flags (⇧ 2, ⌃ 4, ⌥ 8, ⌘ 128). 0 or missing = switched off.
    public static func googleDrive(searchHotKey: Int64?) -> BackgroundShortcut? {
        guard let v = searchHotKey, v != 0, let name = KeyCodes.name(for: UInt16(v & 0xFFFF)) else { return nil }
        let flags = v >> 32
        var mods = Set<Mod>()
        if flags & 2 != 0 { mods.insert(.shift) }
        if flags & 4 != 0 { mods.insert(.ctrl) }
        if flags & 8 != 0 { mods.insert(.alt) }
        if flags & 128 != 0 { mods.insert(.cmd) }
        return BackgroundShortcut(combo: Combo(mods: mods, key: name), app: "Google Drive", what: "Search",
                                  effect: "Both run. To fix it, change Drive's search key to ⌥⌘D⇧ "
                                      + "(Drive → ⚙ → Preferences → ⚙ Settings → Configure hotkey).")
    }
}
