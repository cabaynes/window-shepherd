import Foundation

/// What `FrozenStore` keeps: each combination's frozen copy, and the last
/// screen change (so the Revert row comes back after a relaunch).
public struct FrozenState: Codable, Equatable {
    public var copies: [String: FrozenCopy] = [:]
    public var lastChangeKey: String?
    public var lastChangeAt: Double?

    public init(copies: [String: FrozenCopy] = [:], lastChangeKey: String? = nil, lastChangeAt: Double? = nil) {
        self.copies = copies; self.lastChangeKey = lastChangeKey; self.lastChangeAt = lastChangeAt
    }
}

/// Frozen copies on disk (JSON) next to the live layouts, written atomically
/// on a utility queue, like `LayoutStore`.
public final class FrozenStore {
    public let url: URL
    private let queue = DispatchQueue(label: "window-shepherd.frozen", qos: .utility)

    /// "layouts.json" → "layouts-frozen.json" in the same folder.
    public static func url(beside layouts: URL) -> URL {
        layouts.deletingLastPathComponent()
            .appendingPathComponent(layouts.deletingPathExtension().lastPathComponent + "-frozen.json")
    }

    public init(url: URL) { self.url = url }

    /// Missing or damaged file → nothing frozen (logged), never a crash.
    public func load() -> FrozenState {
        guard let data = try? Data(contentsOf: url) else { return FrozenState() }
        do {
            return try JSONDecoder().decode(FrozenState.self, from: data)
        } catch {
            Log.info("frozen layouts were damaged; starting fresh (\(error.localizedDescription))")
            return FrozenState()
        }
    }

    public func save(_ state: FrozenState) {
        let url = self.url
        queue.async {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(state).write(to: url, options: .atomic)
            } catch {
                Log.info("couldn't save frozen layouts: \(error.localizedDescription)")
            }
        }
    }

    /// Waits for pending writes (tests).
    public func flush() { queue.sync {} }
}
