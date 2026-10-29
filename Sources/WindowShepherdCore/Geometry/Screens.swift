import AppKit

public struct ScreenInfo: Equatable {
    public let displayID: UInt32
    public let uuid: String
    public let name: String
    public let isBuiltin: Bool
    /// Usable area (minus menu bar and Dock), top-left coordinates.
    public let frame: CGRect
    /// Whole screen, top-left coordinates.
    public let full: CGRect

    public init(displayID: UInt32, uuid: String, name: String, isBuiltin: Bool, frame: CGRect, full: CGRect) {
        self.displayID = displayID; self.uuid = uuid; self.name = name
        self.isBuiltin = isBuiltin; self.frame = frame; self.full = full
    }
}

/// A numbered screen: 1 = the laptop, then the monitors left to right.
public struct Destination: Equatable {
    public let screen: ScreenInfo
    public let name: String
    public let num: Int
    public let isLaptop: Bool
}

public enum Screens {
    /// The connected screens, in NSScreen order. Cheap; never talks to apps.
    public static func live() -> [ScreenInfo] {
        let all = NSScreen.screens
        guard let primary = all.first else { return [] }
        let h = primary.frame.height
        return all.compactMap { s in
            guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = n.uint32Value
            var uuid = "?"
            if let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
               let str = CFUUIDCreateString(nil, u) as String? { uuid = str }
            return ScreenInfo(displayID: id, uuid: uuid, name: s.localizedName, isBuiltin: CGDisplayIsBuiltin(id) != 0,
                              frame: Geometry.flip(s.visibleFrame, primaryHeight: h),
                              full: Geometry.flip(s.frame, primaryHeight: h))
        }
    }

    /// The screen with keyboard focus (NSScreen.main), as ScreenInfo.
    public static func main(in screens: [ScreenInfo]) -> ScreenInfo? {
        guard let n = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return screens.first
        }
        return screens.first { $0.displayID == n.uint32Value } ?? screens.first
    }

    /// Every screen, numbered: the laptop first (as "Laptop"), then the others
    /// left to right, each by its own name ("Monitor" when it has none).
    public static func destinations(_ screens: [ScreenInfo]) -> [Destination] {
        let laptop = screens.first { $0.isBuiltin }
        var list: [(ScreenInfo, String, Bool)] = []
        if let laptop { list.append((laptop, "Laptop", true)) }
        let others = screens.filter { $0 != laptop }.sorted { $0.full.minX < $1.full.minX }
        for s in others { list.append((s, s.name.isEmpty ? "Monitor" : s.name, false)) }
        return list.enumerated().map { Destination(screen: $1.0, name: $1.1, num: $0 + 1, isLaptop: $1.2) }
    }

    /// The largest screen by area; a tie goes to a monitor over the built-in, then the first.
    public static func biggest(_ screens: [ScreenInfo]) -> ScreenInfo? {
        func area(_ s: ScreenInfo) -> CGFloat { s.full.width * s.full.height }
        return screens.enumerated().max { a, b in
            if area(a.element) != area(b.element) { return area(a.element) < area(b.element) }
            if a.element.isBuiltin != b.element.isBuiltin { return a.element.isBuiltin }
            return a.offset > b.offset
        }?.element
    }

    /// Identity of a combination of connected screens.
    public static func setupKey(_ screens: [ScreenInfo]) -> String {
        screens.map(\.uuid).sorted().joined(separator: "+")
    }

    public static func setupLabel(_ screens: [ScreenInfo]) -> String {
        screens.map { $0.name.isEmpty ? "?" : $0.name }.sorted().joined(separator: " + ")
    }

    /// The screen after `s` in NSScreen order, wrapping around (hs screen:next()).
    public static func next(after s: ScreenInfo, in screens: [ScreenInfo]) -> ScreenInfo {
        guard let i = screens.firstIndex(of: s) else { return screens.first ?? s }
        return screens[(i + 1) % screens.count]
    }

    /// A bulk move's size on screen n: full screen on the laptop, 90% on a monitor.
    public static func defaultFraction(_ d: Destination) -> Double { d.isLaptop ? 1.0 : 0.9 }
}
