import CoreGraphics
import Foundation

/// Size, position, size again: a move to another screen can be refused a size
/// the first time (Rectangle and Hammerspoon do the same). Then check: right
/// after a move to another screen an app can still fit the window to the
/// screen it left, so a window that has to grow there comes out short (seen
/// live: Dell bottom half → laptop stopped at the Dell's bottom edge). Try
/// again after a short wait, at most 0.15 s in all, and never for a window
/// that can't be resized. Returns false only when the move itself failed.
/// Runs on a worker; `pause` sleeps it.
func applyFrame(_ r: CGRect,
                setSize: (CGSize) -> Void,
                setPosition: (CGPoint) -> Bool,
                read: () -> CGRect?,
                canResize: () -> Bool,
                pause: (TimeInterval) -> Void) -> Bool {
    setSize(r.size)
    guard setPosition(r.origin) else { return false }
    setSize(r.size)
    for wait in [0.05, 0.1] {
        guard let f = read(), !f.isClose(to: r), canResize() else { return true }
        pause(wait)
        _ = setPosition(r.origin)
        setSize(r.size)
    }
    return true
}

extension CGRect {
    /// Within a point on every edge: apps round to whole points.
    func isClose(to o: CGRect) -> Bool {
        abs(minX - o.minX) <= 1 && abs(minY - o.minY) <= 1 && abs(width - o.width) <= 1 && abs(height - o.height) <= 1
    }
}
