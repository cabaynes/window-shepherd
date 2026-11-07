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

    /// Missing or unreadable file → start empty (logged), never a crash. A damaged entry
    /// costs only itself: the rest are kept (logged with how many were dropped).
    public func load() -> [String: [String: LayoutEntry]] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let raw: [String: [String: Lenient]]
        do {
            raw = try JSONDecoder().decode([String: [String: Lenient]].self, from: data)
        } catch {
            Log.info("remembered layouts were damaged; starting fresh (\(error.localizedDescription))")
            return [:]
        }
        var out: [String: [String: LayoutEntry]] = [:]
        var dropped = 0
        for (key, entries) in raw {
            for (id, e) in entries {
                if let entry = e.entry { out[key, default: [:]][id] = entry } else { dropped += 1 }
            }
        }
        if dropped > 0 { Log.info("remembered layouts: \(dropped) damaged entr\(dropped == 1 ? "y" : "ies") dropped, the rest kept") }
        return out
    }

    /// An entry that may not decode.
    private struct Lenient: Decodable {
        let entry: LayoutEntry?
        init(from decoder: Decoder) throws { entry = try? LayoutEntry(from: decoder) }
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
