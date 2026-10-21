import AppKit

/// The menu-bar mark: the app icon's shepherd's crook hooking the ⧉ windows,
/// drawn in code so it's sharp at every scale. A template image (macOS tints
/// it for light and dark menu bars); the busy version is white on red.
enum MenuBarGlyph {
    static let size = NSSize(width: 22, height: 16)

    static func image(busy: Bool) -> NSImage {
        let img = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            if busy {
                ctx.setFillColor(red.cgColor)
                ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: 4, cornerHeight: 4, transform: nil))
                ctx.fillPath()
            }
            draw(ctx, color: busy ? .white : .black, busy: busy)
            return true
        }
        img.isTemplate = !busy
        img.accessibilityDescription = "Window Shepherd"
        return img
    }

    private static let red = NSColor(calibratedRed: 0.85, green: 0.1, blue: 0.1, alpha: 1)

    private static func draw(_ ctx: CGContext, color: NSColor, busy: Bool) {
        let line: CGFloat = 1.3
        let back = CGRect(x: 7.5, y: 5.5, width: 8.5, height: 6.5)
        let front = CGRect(x: 11, y: 8.5, width: 9.5, height: 6.5)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(line)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Back window, then clear the front one's area so it sits on top (⧉).
        window(ctx, back)
        // (On red when busy; a template image is cut out instead.)
        if busy {
            ctx.setFillColor(red.cgColor)
            ctx.fill(front.insetBy(dx: -line / 2, dy: -line / 2))
        } else {
            ctx.setBlendMode(.clear)
            ctx.fill(front.insetBy(dx: -line / 2, dy: -line / 2))
            ctx.setBlendMode(.normal)
        }
        window(ctx, front)

        // The crook: a staff up the left, its hook coming down to rest on the
        // back window's title bar, like the app icon.
        let staffX: CGFloat = 2.5, r: CGFloat = 3
        let hook = CGPoint(x: staffX + r, y: 4.2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: staffX, y: 15))
        path.addLine(to: CGPoint(x: staffX, y: hook.y))
        path.addArc(center: hook, radius: r, startAngle: .pi, endAngle: .pi * 2.15, clockwise: false)
        ctx.setLineWidth(1.6)
        ctx.addPath(path)
        ctx.strokePath()
    }

    private static func window(_ ctx: CGContext, _ r: CGRect) {
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 1.6, cornerHeight: 1.6, transform: nil))
        ctx.strokePath()
        ctx.move(to: CGPoint(x: r.minX, y: r.minY + 2.2))   // title bar
        ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY + 2.2))
        ctx.strokePath()
    }
}
