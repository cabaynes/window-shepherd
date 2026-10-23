import CoreGraphics

/// A rect as fractions of a screen's usable area.
public struct UnitRect: Codable, Equatable {
    public var x, y, w, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
}

/// Where a window sits: which screen (display UUID) and where on it.
public struct Spot: Codable, Equatable {
    public var scr: String
    public var unit: UnitRect
    public init(scr: String, unit: UnitRect) { self.scr = scr; self.unit = unit }
}

/// Geometry in global top-left coordinates (the space CoreGraphics window
/// lists and the Accessibility API use).
public enum Geometry {
    public static func place(_ u: UnitRect, in f: CGRect) -> CGRect {
        CGRect(x: f.minX + u.x * f.width, y: f.minY + u.y * f.height, width: u.w * f.width, height: u.h * f.height)
    }

    /// Keep the size (shrunk to fit), centred.
    public static func centered(_ size: CGSize, in f: CGRect) -> CGRect {
        let w = min(size.width, f.width), h = min(size.height, f.height)
        return CGRect(x: f.minX + (f.width - w) / 2, y: f.minY + (f.height - h) / 2, width: w, height: h)
    }

    public static func unit(of r: CGRect, in f: CGRect) -> UnitRect {
        UnitRect(x: (r.minX - f.minX) / f.width, y: (r.minY - f.minY) / f.height,
                 w: r.width / f.width, h: r.height / f.height)
    }

    /// Shrink to fit, then slide inside (Hammerspoon's ensureIsInScreenBounds).
    public static func fit(_ r: CGRect, inside f: CGRect) -> CGRect {
        let w = min(r.width, f.width), h = min(r.height, f.height)
        let x = min(max(r.minX, f.minX), f.maxX - w)
        let y = min(max(r.minY, f.minY), f.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// AppKit (bottom-left origin) → top-left origin, given the primary screen's height.
    public static func flip(_ r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// The screen holding most of `r` (hs.screen.find(rect)); nil if it's on none.
    public static func screen(mostOf r: CGRect, in screens: [ScreenInfo]) -> ScreenInfo? {
        var best: ScreenInfo?, bestArea: CGFloat = 0
        for s in screens {
            let i = s.full.intersection(r)
            let area = i.isNull ? 0 : i.width * i.height
            if area > bestArea { best = s; bestArea = area }
        }
        return best
    }

    /// Which screen a window is on (its centre is inside the screen) and
    /// where, as a fraction of that screen's usable area.
    public static func whereIs(_ windowFrame: CGRect, in screens: [ScreenInfo]) -> Spot? {
        let c = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        guard let s = screens.first(where: { $0.full.contains(c) }) else { return nil }
        return Spot(scr: s.uuid, unit: unit(of: windowFrame, in: s.frame))
    }

    public static func sameSpot(_ a: Spot?, _ b: Spot?) -> Bool {
        guard let a, let b, a.scr == b.scr else { return false }
        let ua = a.unit, ub = b.unit
        return abs(ua.x - ub.x) < 0.005 && abs(ua.y - ub.y) < 0.005
            && abs(ua.w - ub.w) < 0.005 && abs(ua.h - ub.h) < 0.005
    }
}
