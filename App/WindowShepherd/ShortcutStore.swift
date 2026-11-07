import Foundation
import WindowShepherdCore

/// The user's shortcuts in UserDefaults, as JSON. All defaults = nothing
/// stored, so future default changes still reach people who never customized.
final class ShortcutStore {
    private let defaults: UserDefaults
    private let key = "shortcuts"
    /// Saved keys this keyboard can't bind: written back on save (see `encodeForSave`).
    private var held: [String: Any] = [:]

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> ShortcutConfig {
        let saved = defaults.data(forKey: key).flatMap { try? JSONSerialization.jsonObject(with: $0) }
        let valid: (String) -> Bool = { KeyCodes.code(for: $0) != nil }
        let (cfg, notes) = sanitize(saved: saved, isValidKey: valid)
        held = unbindableSaved(saved: saved, isValidKey: valid)
        for n in notes { Log.info("shortcuts: " + n) }
        return cfg
    }

    func save(_ cfg: ShortcutConfig) {
        if let data = encodeForSave(cfg, keeping: held) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
