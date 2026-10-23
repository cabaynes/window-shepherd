import Foundation
import WindowShepherdCore

/// The user's shortcuts in UserDefaults, as JSON. All defaults = nothing
/// stored, so future default changes still reach people who never customized.
final class ShortcutStore {
    private let defaults: UserDefaults
    private let key = "shortcuts"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> ShortcutConfig {
        let saved = defaults.data(forKey: key).flatMap { try? JSONSerialization.jsonObject(with: $0) }
        let (cfg, notes) = sanitize(saved: saved, isValidKey: { KeyCodes.code(for: $0) != nil })
        for n in notes { Log.info("shortcuts: " + n) }
        return cfg
    }

    func save(_ cfg: ShortcutConfig) {
        if cfg.isDefault {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(cfg) {
            defaults.set(data, forKey: key)
        }
    }
}
