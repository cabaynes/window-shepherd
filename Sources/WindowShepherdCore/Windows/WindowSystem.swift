import CoreGraphics
import Foundation

/// A window the engine can move. Every method talks to the app, so call them
/// only on a worker queue (`AXWorker`), never on the main thread.
public protocol WindowHandle: AnyObject {
    var windowID: UInt32? { get }
    func frame() -> CGRect?
    func setFrame(_ r: CGRect) throws
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
    /// When the left mouse button was last pressed or dragged, in any app:
    /// a window that moved without it was moved by macOS or its app, not by you.
    func lastMouseUse() -> Date?                 // main
    func appWindows(pid: pid_t) throws -> [WindowHandle]   // worker
    func focusedWindow(pid: pid_t) -> WindowHandle?        // worker
    func activate(pid: pid_t)                              // worker
}
