// Renders the app-icon options and a menu-bar glyph for Charles to choose from.
//   swift design/icon-options/render.swift
// Writes option-a.png, option-b.png, option-c.png (1024 px) and
// menubar-crook.png (36 px, a template image: black on clear) next to this file.
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ name: String, size: Int, _ draw: (CGContext, CGFloat) -> Void) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Draw in a top-left coordinate space, like a design tool.
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: 1, y: -1)
    draw(ctx, CGFloat(size))
    let url = outDir.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(url.lastPathComponent)")
}

/// The macOS icon body: a rounded square inset in the 1024 canvas, with a gradient.
func body(_ ctx: CGContext, _ s: CGFloat, top: UInt32, bottom: UInt32) -> CGRect {
    let r = CGRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let path = CGPath(roundedRect: r, cornerWidth: s * 0.18, cornerHeight: s * 0.18, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: s * 0.012), blur: s * 0.03, color: rgb(0x000000, 0.35))
    ctx.addPath(path)
    ctx.setFillColor(rgb(top))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgb(top), rgb(bottom)] as CFArray,
                       locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: r.minY), end: CGPoint(x: 0, y: r.maxY), options: [])
    ctx.restoreGState()
    return r
}

/// A small app window: rounded rect, title bar with three dots.
func window(_ ctx: CGContext, _ r: CGRect, fill: CGColor, bar: CGColor) {
    let radius = r.width * 0.07
    let path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: r.width * 0.02), blur: r.width * 0.06, color: rgb(0x000000, 0.25))
    ctx.addPath(path)
    ctx.setFillColor(fill)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.setFillColor(bar)
    ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.16))
    ctx.restoreGState()
    let d = r.height * 0.07
    for (i, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        ctx.setFillColor(rgb(UInt32(c)))
        ctx.fillEllipse(in: CGRect(x: r.minX + d * (0.9 + 1.6 * CGFloat(i)), y: r.minY + r.height * 0.08 - d / 2, width: d, height: d))
    }
}

/// A shepherd's crook: a straight staff up to a round hook. `hook` is the
/// hook's centre, `radius` its size; the staff drops from the hook's left side.
func crook(_ ctx: CGContext, hook: CGPoint, radius: CGFloat, staffBottom: CGFloat, width: CGFloat, color: CGColor) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: hook.x - radius, y: staffBottom))
    p.addLine(to: CGPoint(x: hook.x - radius, y: hook.y))
    // Over the top, clockwise, and down the right side a little.
    p.addArc(center: hook, radius: radius, startAngle: .pi, endAngle: .pi * 0.15, clockwise: false)
    ctx.saveGState()
    ctx.addPath(p)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(color)
    ctx.strokePath()
    ctx.restoreGState()
}

// (a) The ⧉ mark the menu bar already uses, on a deep-blue tile.
render("option-a.png", size: 1024) { ctx, s in
    let r = body(ctx, s, top: 0x3A7BFF, bottom: 0x1C3FAA)
    let w = r.width * 0.42
    ctx.setLineWidth(s * 0.045)
    ctx.setStrokeColor(rgb(0xFFFFFF))
    ctx.setLineJoin(.round)
    let back = CGRect(x: r.midX - w * 0.42, y: r.midY - w * 0.78, width: w, height: w)
    let front = CGRect(x: r.midX - w * 0.6, y: r.midY - w * 0.22, width: w, height: w)
    ctx.addPath(CGPath(roundedRect: back, cornerWidth: s * 0.03, cornerHeight: s * 0.03, transform: nil))
    ctx.strokePath()
    ctx.setFillColor(rgb(0x2A5BE0))
    ctx.addPath(CGPath(roundedRect: front, cornerWidth: s * 0.03, cornerHeight: s * 0.03, transform: nil))
    ctx.drawPath(using: .fillStroke)
}

// (b) A shepherd's crook gathering two windows, on a dusk-sky tile.
render("option-b.png", size: 1024) { ctx, s in
    let r = body(ctx, s, top: 0x5B8DEF, bottom: 0x283E8C)
    window(ctx, CGRect(x: r.minX + r.width * 0.30, y: r.minY + r.height * 0.34, width: r.width * 0.50, height: r.height * 0.36),
           fill: rgb(0xEEF2FB), bar: rgb(0xD4DCEF))
    window(ctx, CGRect(x: r.minX + r.width * 0.40, y: r.minY + r.height * 0.48, width: r.width * 0.46, height: r.height * 0.33),
           fill: rgb(0xFFFFFF), bar: rgb(0xE3E8F4))
    crook(ctx, hook: CGPoint(x: r.minX + r.width * 0.36, y: r.minY + r.height * 0.27), radius: r.width * 0.13,
          staffBottom: r.minY + r.height * 0.88, width: s * 0.05, color: rgb(0xF4C46A))
}

// (c) A white crook hooking the ⧉ mark, on a green "pasture" tile.
render("option-c.png", size: 1024) { ctx, s in
    let r = body(ctx, s, top: 0x3CC48A, bottom: 0x1E7A5C)
    let w = r.width * 0.34
    ctx.setLineWidth(s * 0.04)
    ctx.setStrokeColor(rgb(0xFFFFFF))
    ctx.setLineJoin(.round)
    let back = CGRect(x: r.minX + r.width * 0.45, y: r.minY + r.height * 0.33, width: w, height: w)
    let front = CGRect(x: r.minX + r.width * 0.35, y: r.minY + r.height * 0.45, width: w, height: w)
    ctx.addPath(CGPath(roundedRect: back, cornerWidth: s * 0.025, cornerHeight: s * 0.025, transform: nil))
    ctx.strokePath()
    ctx.setFillColor(rgb(0x2A9E72))
    ctx.addPath(CGPath(roundedRect: front, cornerWidth: s * 0.025, cornerHeight: s * 0.025, transform: nil))
    ctx.drawPath(using: .fillStroke)
    crook(ctx, hook: CGPoint(x: r.minX + r.width * 0.36, y: r.minY + r.height * 0.27), radius: r.width * 0.12,
          staffBottom: r.minY + r.height * 0.88, width: s * 0.045, color: rgb(0xFFFFFF))
}

// Menu-bar glyph: a crook over a small window, black on clear (used as a template image).
render("menubar-crook.png", size: 36) { ctx, s in
    ctx.setStrokeColor(rgb(0x000000))
    ctx.setLineWidth(2.4)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 13, y: 15, width: 19, height: 15), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
    ctx.strokePath()
    crook(ctx, hook: CGPoint(x: 13, y: 9), radius: 5.5, staffBottom: 33, width: 2.6, color: rgb(0x000000))
}
