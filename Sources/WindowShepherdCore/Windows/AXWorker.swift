import Foundation

/// A serial background queue for Accessibility calls, bridged to async/await.
/// The main thread never waits on another app: it awaits the result instead.
public final class AXWorker {
    private let queue: DispatchQueue

    public init(label: String) {
        queue = DispatchQueue(label: "window-shepherd." + label, qos: .userInitiated)
    }

    public func run<T>(_ body: @escaping () -> T) async -> T {
        await withCheckedContinuation { cont in
            queue.async { cont.resume(returning: body()) }
        }
    }
}
