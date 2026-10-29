import Foundation
import WindowShepherdCore

/// The "Windows opened while undocked" setting in UserDefaults, as JSON.
/// The default = nothing stored, like the shortcuts.
final class UndockedStore {
    /// Posted after a save, so the engine picks the new setting up.
    static let changed = Notification.Name("com.windowshepherd.WindowShepherd.undockedChanged")

    private let defaults: UserDefaults
    private let key = "undockedWindows"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> UndockedWindows {
        guard let data = defaults.data(forKey: key) else { return .defaults }
        return (try? JSONDecoder().decode(UndockedWindows.self, from: data)) ?? .defaults
    }

    func save(_ u: UndockedWindows) {
        if u == .defaults {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(u) {
            defaults.set(data, forKey: key)
        }
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
}
