import CoreGraphics
import Foundation

/// A window the engine can move. Every method talks to the app, so call them
/// only on a worker queue (`AXWorker`), never on the main thread.
public protocol WindowHandle: AnyObject {
    var windowID: UInt32? { get }
    func frame() -> CGRect?
    func setFrame(_ r: CGRect) throws
    /// Whether this is an ordinary document window (not a dialog, palette or
    /// panel); nil when the app doesn't say.
    var isStandard: Bool? { get }
    /// Whether the window has the green full-screen button (Finder's Get Info
    /// panel is standard but has none).
    var hasFullScreenButton: Bool { get }
    /// The title the app reports (needs only Accessibility, unlike the window list's titles).
    var title: String? { get }
    /// Whether the app lets the window's size change.
    var isResizable: Bool { get }
}

public struct AXFailure: Error, Equatable {
    public let code: Int32
    public init(code: Int32) { self.code = code }
}

/// Everything the engine needs from macOS. Methods marked *main* are cheap
/// and never talk to other apps; methods marked *worker* may block for up to
/// the Accessibility timeout and must run on an `AXWorker`.
public protocol WindowSystem: AnyObject {
    func visibleWindows() -> [CGWindow]          // main
    /// Every normal window that exists, on any Space or minimized (to forget closed ones).
    func allWindowIDs() -> Set<UInt32>           // main
    func screens() -> [ScreenInfo]               // main
    func mainScreen() -> ScreenInfo?             // main
    func frontmostPID() -> pid_t?                // main
    func runningApps() -> [pid_t: String]        // main
    func isRunning(bundleID: String) -> Bool     // main
    func appName(pid: pid_t) -> String?          // main
    func bundleID(pid: pid_t) -> String?         // main
    /// The bundle ID of the app with this name: running, else installed. For the one-time seed only.
    func bundleID(appName: String) -> String?    // main
    func launchDate(pid: pid_t) -> Date?         // main
    /// When the left mouse button was last pressed or dragged, in any app:
    /// a window that moved without it was moved by macOS or its app, not by you.
    func lastMouseUse() -> Date?                 // main
    /// When the left mouse button was last dragged (a click moves no window).
    func lastMouseDrag() -> Date?                // main
    func appWindows(pid: pid_t) throws -> [WindowHandle]   // worker
    func focusedWindow(pid: pid_t) -> WindowHandle?        // worker
    func activate(pid: pid_t)                              // worker
    /// Switches the app's AXEnhancedUserInterface off if it's on (it animates every move and
    /// drops a position set mid-animation); true if it was on, so the caller switches it back.
    func enhancedUIOff(pid: pid_t) -> Bool                 // worker
    func enhancedUIOn(pid: pid_t)                          // worker
}
