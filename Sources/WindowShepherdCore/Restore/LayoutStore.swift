import Foundation

/// Remembered layouts on disk (JSON), so a restart keeps them. Writes are
/// atomic and happen on a utility queue.
public final class LayoutStore {
    public let url: URL
    private let queue = DispatchQueue(label: "window-shepherd.layouts", qos: .utility)
    public private(set) var lastSaved: Double = 0
    public private(set) var saveCount = 0

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Window Shepherd/layouts.json")
    }

    public init(url: URL = LayoutStore.defaultURL) { self.url = url }

    /// Missing or damaged file → start empty (logged), never a crash.
    public func load() -> [String: [String: LayoutEntry]] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        do {
            return try JSONDecoder().decode([String: [String: LayoutEntry]].self, from: data)
        } catch {
            Log.info("remembered layouts were damaged; starting fresh (\(error.localizedDescription))")
            return [:]
        }
    }

    public func save(_ layouts: [String: [String: LayoutEntry]]) {
        lastSaved = Date().timeIntervalSince1970
        saveCount += 1
        let url = self.url
        queue.async {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(layouts).write(to: url, options: .atomic)
            } catch {
                Log.info("couldn't save layouts: \(error.localizedDescription)")
            }
        }
    }

    /// Waits for pending writes (tests).
    public func flush() { queue.sync {} }
}
