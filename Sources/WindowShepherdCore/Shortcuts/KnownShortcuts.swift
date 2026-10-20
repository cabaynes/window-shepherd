import Foundation

/// The built-in list of popular apps' shortcuts (so apps that aren't open
/// are still covered) and names for macOS's numbered system shortcuts.
/// Ported from the Hammerspoon version's known-shortcuts.lua; see
/// scripts/port-known-shortcuts.lua.
public struct KnownShortcuts {
    public let apps: [AppShortcut]
    public let system: [Int: String]

    public static let shared: KnownShortcuts = load()

    private struct File: Decodable {
        struct App: Decodable { let app: String; let what: String; let keys: String }
        let apps: [App]
        let system: [String: String]
    }

    static func load() -> KnownShortcuts {
        guard let url = Bundle.module.url(forResource: "known-shortcuts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            Log.info("built-in shortcut list is missing or damaged")
            return KnownShortcuts(apps: [], system: [:])
        }
        let apps = file.apps.compactMap { e in
            Combo.parse(e.keys).map { AppShortcut(combo: $0, app: e.app, what: e.what) }
        }
        var system: [Int: String] = [:]
        for (k, v) in file.system { if let id = Int(k) { system[id] = v } }
        return KnownShortcuts(apps: apps, system: system)
    }
}

/// Names for macOS's default shortcuts. The symbolichotkeys preferences list
/// only the ones a user changed, so defaults are named from here.
public enum SystemShortcutNames {
    private static let defaults: [String: String] = {
        var d = [
            "⌘Space": "Spotlight search", "⌥⌘Space": "Finder search window",
            "⌃↑": "Mission Control", "⌃↓": "Application windows",
            "⌃←": "Move left a space", "⌃→": "Move right a space",
            "⌘3⇧": "Screenshot of the screen", "⌘4⇧": "Screenshot of an area", "⌘5⇧": "Screenshot options",
            "⌃⌘3⇧": "Copy screenshot of the screen", "⌃⌘4⇧": "Copy screenshot of an area",
            "⌃Space": "Previous input source", "⌃⌥Space": "Next input source",
        ]
        for n in 1...9 { d["⌃\(n)"] = "Switch to Desktop \(n)" }
        return d
    }()

    public static func defaultName(for c: Combo) -> String? { defaults[c.formatted] }
}
