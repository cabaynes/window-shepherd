import CoreGraphics

/// Where windows opened while a screen was unplugged go when it comes back
/// (they have no remembered spot on it). Set in Customize Shortcuts.
public struct UndockedWindows: Codable, Equatable {
    public enum Target: Codable, Hashable {
        case biggest
        case named(uuid: String, name: String)
    }

    public enum Size: String, Codable, CaseIterable {
        case ninety = "90% centered", full = "Full screen", sixty = "60% centered", keep = "Same size, centered"

        /// The fraction of the screen, or nil for "same size, centered".
        var unit: UnitRect? {
            switch self {
            case .ninety: return UnitRect(x: 0.05, y: 0.05, w: 0.9, h: 0.9)
            case .full: return UnitRect(x: 0, y: 0, w: 1, h: 1)
            case .sixty: return UnitRect(x: 0.2, y: 0.2, w: 0.6, h: 0.6)
            case .keep: return nil
            }
        }
    }

    public var enabled = true
    public var target = Target.biggest
    public var size = Size.ninety

    public init(enabled: Bool = true, target: Target = .biggest, size: Size = .ninety) {
        self.enabled = enabled; self.target = target; self.size = size
    }

    public static let defaults = UndockedWindows()

    /// The chosen screen if it's connected, else the biggest.
    public func screen(in screens: [ScreenInfo]) -> ScreenInfo? {
        if case let .named(uuid, _) = target, let s = screens.first(where: { $0.uuid == uuid }) { return s }
        return Screens.biggest(screens)
    }
}
