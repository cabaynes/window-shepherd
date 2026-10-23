import CoreGraphics
import Foundation

/// Whole points (as Hammerspoon does), then size, position, size again: a move
/// to another screen can be refused a size the first time (Rectangle and
/// Hammerspoon do the same). The position is sent once and never again:
/// re-sending it while Chrome was still making the first move left its
/// windows stuck part-way, then refusing moves between screens (live,
/// 2026-10-20). One exception, for the size only: right after a move to
/// another screen an app can still fit the window to the screen it left, so
/// a window that has to grow there comes out short (Dell bottom half →
/// laptop stopped at the Dell's bottom edge). If it landed where it was sent
/// but short, wait 0.1 s and send the size once more — never for a window
/// that can't be resized. Returns false only when the move itself failed.
/// Runs on a worker; `pause` sleeps it.
func applyFrame(_ wanted: CGRect,
                setSize: (CGSize) -> Void,
                setPosition: (CGPoint) -> Bool,
                read: () -> CGRect?,
                canResize: () -> Bool,
                pause: (TimeInterval) -> Void) -> Bool {
    let r = CGRect(x: wanted.minX.rounded(.down), y: wanted.minY.rounded(.down),
                   width: wanted.width.rounded(.down), height: wanted.height.rounded(.down))
    setSize(r.size)
    guard setPosition(r.origin) else { return false }
    setSize(r.size)
    guard let f = read(), f.origin.isClose(to: r.origin),                  // still on its way: leave it be
          f.width < r.width - 1 || f.height < r.height - 1, canResize() else { return true }
    pause(0.1)
    setSize(r.size)
    return true
}

extension CGPoint {
    /// Within a point each way: apps round to whole points.
    func isClose(to o: CGPoint) -> Bool { abs(x - o.x) <= 1 && abs(y - o.y) <= 1 }
}
