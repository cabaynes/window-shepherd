import AppKit
import WindowShepherdCore

/// End-to-end scenarios (added as the engine grows).
enum Scenarios {
    static func run(_ name: String) {
        print("unknown scenario \(name)")
        exit(2)
    }
}
