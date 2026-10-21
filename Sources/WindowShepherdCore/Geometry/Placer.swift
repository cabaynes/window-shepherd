import CoreGraphics

/// Where an action puts a window, as a fraction of its screen, or centred at
/// its own size.
public enum Placement: Equatable {
    case unit(UnitRect), center
}

extension ActionID {
    public var placement: Placement {
        switch self {
        case .fullScreen: return .unit(UnitRect(x: 0, y: 0, w: 1, h: 1))
        case .almost: return .unit(UnitRect(x: 0.05, y: 0.05, w: 0.9, h: 0.9))
        case .sixty: return .unit(UnitRect(x: 0.2, y: 0.2, w: 0.6, h: 0.6))
        case .center: return .center
        case .leftHalf: return .unit(UnitRect(x: 0, y: 0, w: 0.5, h: 1))
        case .rightHalf: return .unit(UnitRect(x: 0.5, y: 0, w: 0.5, h: 1))
        case .topHalf: return .unit(UnitRect(x: 0, y: 0, w: 1, h: 0.5))
        case .bottomHalf: return .unit(UnitRect(x: 0, y: 0.5, w: 1, h: 0.5))
        case .topLeft: return .unit(UnitRect(x: 0, y: 0, w: 0.5, h: 0.5))
        case .topRight: return .unit(UnitRect(x: 0.5, y: 0, w: 0.5, h: 0.5))
        case .bottomLeft: return .unit(UnitRect(x: 0, y: 0.5, w: 0.5, h: 0.5))
        case .bottomRight: return .unit(UnitRect(x: 0.5, y: 0.5, w: 0.5, h: 0.5))
        }
    }
}

/// Which screen a placer works on: the one the window is already on, or a
/// fixed one (by display UUID, so a screen that's gone is noticed).
public enum TargetScreen: Equatable {
    /// `next`: the screen after the one the window is on, worked out from the
    /// window itself (the one with keyboard focus may not be the first listed).
    case own, next, fixed(uuid: String)
}

public enum Placer: Equatable {
    case unit(UnitRect, TargetScreen, fitInside: Bool = false)
    case center(TargetScreen)

    public init(_ p: Placement, on target: TargetScreen) {
        switch p {
        case .unit(let u): self = .unit(u, target)
        case .center: self = .center(target)
        }
    }

    /// A centred f × f placement (1.0 = full screen, 0.9 = Almost Maximize).
    public static func fraction(_ f: Double, on t: TargetScreen) -> Placer {
        let m = (1 - f) / 2
        return .unit(UnitRect(x: m, y: m, w: f, h: f), t)
    }

    /// The window's new frame, or nil when the target screen isn't connected.
    /// `.own` = the screen holding most of the window, else the main screen
    /// (a window stranded off-screen comes back).
    public func frame(for window: CGRect, screens: [ScreenInfo], main: ScreenInfo?) -> CGRect? {
        func resolve(_ t: TargetScreen) -> ScreenInfo? {
            switch t {
            case .own: return Geometry.screen(mostOf: window, in: screens) ?? main
            case .next: return (Geometry.screen(mostOf: window, in: screens) ?? main).map { Screens.next(after: $0, in: screens) }
            case .fixed(let uuid): return screens.first { $0.uuid == uuid }
            }
        }
        switch self {
        case let .unit(u, t, fitInside):
            guard let s = resolve(t) else { return nil }
            let r = Geometry.place(u, in: s.frame)
            return fitInside ? Geometry.fit(r, inside: s.frame) : r
        case .center(let t):
            guard let s = resolve(t) else { return nil }
            return Geometry.centered(window.size, in: s.frame)
        }
    }
}

/// "full", "90%", "60%".
public func sizeLabel(_ f: Double) -> String {
    f >= 1 ? "full" : "\(Int((f * 100).rounded()))%"
}
