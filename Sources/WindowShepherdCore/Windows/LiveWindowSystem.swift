import AppKit
import ApplicationServices

/// The private call every window manager uses to match an Accessibility
/// window to its CoreGraphics window number.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Any single question to an app gives up after this long.
public let axTimeout: Float = 0.5

final class AXWindow: WindowHandle {
    let element: AXUIElement
    init(_ e: AXUIElement) {
        element = e
        AXUIElementSetMessagingTimeout(e, axTimeout)   // a timeout applies only to the element it's set on
    }

    var windowID: UInt32? {
        var id = CGWindowID(0)
        return _AXUIElementGetWindow(element, &id) == .success ? id : nil
    }

    func frame() -> CGRect? {
        guard let p: CGPoint = value(kAXPositionAttribute, .cgPoint),
              let s: CGSize = value(kAXSizeAttribute, .cgSize) else { return nil }
        return CGRect(origin: p, size: s)
    }

    /// Size, position, size again: a move to another screen can be refused a
    /// size the first time (Rectangle and Hammerspoon do the same). Only a
    /// failed move counts as failure; fixed-size windows refuse sizes.
    func setFrame(_ r: CGRect) throws {
        set(kAXSizeAttribute, r.size)
        let err = set(kAXPositionAttribute, r.origin)
        set(kAXSizeAttribute, r.size)
        if err != .success { throw AXFailure(code: err.rawValue) }
    }

    private func value<T>(_ attr: String, _ type: AXValueType) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success,
              let v = ref, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        let ax = v as! AXValue
        let out = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { out.deallocate() }
        return AXValueGetValue(ax, type, out) ? out.pointee : nil
    }

    @discardableResult
    private func set(_ attr: String, _ point: CGPoint) -> AXError {
        var p = point
        guard let v = AXValueCreate(.cgPoint, &p) else { return .failure }
        return AXUIElementSetAttributeValue(element, attr as CFString, v)
    }

    @discardableResult
    private func set(_ attr: String, _ size: CGSize) -> AXError {
        var s = size
        guard let v = AXValueCreate(.cgSize, &s) else { return .failure }
        return AXUIElementSetAttributeValue(element, attr as CFString, v)
    }
}

/// The real thing: CoreGraphics for the fast inventory, Accessibility for
/// moving. Invariant: every element we talk to has the 0.5 s messaging
/// timeout — the system-wide element (the default for all) and, as a second
/// guard, each app and window element we create.
public final class LiveWindowSystem: WindowSystem {
    public init() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), axTimeout)
    }

    public func visibleWindows() -> [CGWindow] { CGWindow.current() }
    public func screens() -> [ScreenInfo] { Screens.live() }
    public func mainScreen() -> ScreenInfo? { Screens.main(in: Screens.live()) }
    public func frontmostPID() -> pid_t? { NSWorkspace.shared.frontmostApplication?.processIdentifier }

    public func runningApps() -> [pid_t: String] {
        var out: [pid_t: String] = [:]
        for a in NSWorkspace.shared.runningApplications { out[a.processIdentifier] = a.localizedName ?? "?" }
        return out
    }

    public func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    public func appName(pid: pid_t) -> String? { NSRunningApplication(processIdentifier: pid)?.localizedName }

    static func appElement(_ pid: pid_t) -> AXUIElement {
        let e = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(e, axTimeout)
        return e
    }

    public func appWindows(pid: pid_t) throws -> [WindowHandle] {
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(Self.appElement(pid), kAXWindowsAttribute as CFString, &ref)
        guard err == .success else { throw AXFailure(code: err.rawValue) }
        return (ref as? [AXUIElement] ?? []).map(AXWindow.init)
    }

    public func focusedWindow(pid: pid_t) -> WindowHandle? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(Self.appElement(pid), kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let v = ref, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return AXWindow(v as! AXUIElement)
    }

    public func activate(pid: pid_t) {
        DispatchQueue.main.async {
            NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
        }
        AXUIElementSetAttributeValue(Self.appElement(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }
}
