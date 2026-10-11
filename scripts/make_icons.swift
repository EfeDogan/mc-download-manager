// MC Download Manager icon generator (CoreGraphics).
// Motif: a down arrow inside a ring. The shaft "streams in" from the top — dots, then a dash,
// then a continuous line that ends in the arrowhead.
// Usage: swiftc -O scripts/make_icons.swift -o build/make_icons && build/make_icons <out_dir>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func makeContext(_ size: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    return ctx
}

/// Draws the ring + streaming arrow inside `box` using the current fill/stroke colors.
/// `tint` is called per element with a 0…1 "progress" (0 = top dot, 1 = arrowhead) so callers can grade colors.
func drawGlyph(_ ctx: CGContext, in box: CGRect, tint: (CGFloat, CGFloat) -> CGColor) {
    let cx = box.midX, cy = box.midY
    let R = box.width * 0.5                     // ring outer radius
    let ringW = box.width * 0.07
    let sw = box.width * 0.085                  // shaft / head stroke width
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // Ring
    ctx.setLineWidth(ringW)
    ctx.setStrokeColor(tint(0.5, 0.95))
    ctx.strokeEllipse(in: CGRect(x: cx - R + ringW / 2, y: cy - R + ringW / 2, width: 2 * R - ringW, height: 2 * R - ringW))

    // Arrow geometry (CG y-up): shaft runs from top down to the tip.
    let inner = R - ringW
    let top = cy + inner * 0.84
    let tip = cy - inner * 0.74
    // Segment plan in units of sw, from the top: 3 dots, a dash, then a solid run into the head.
    let dotD = sw * 0.62, gap = sw * 0.48, dash = sw * 1.3
    var y = top
    var dots: [CGFloat] = []
    for _ in 0..<3 { dots.append(y - dotD / 2); y -= dotD + gap }
    let dashTop = y
    let dashBottom = y - dash
    y = dashBottom - gap
    let solidTop = y

    func progress(_ yy: CGFloat) -> CGFloat { (top - yy) / (top - tip) }

    // Dots (fading in from the top)
    for (i, dy) in dots.enumerated() {
        let a: CGFloat = 0.45 + 0.55 * CGFloat(i) / 2
        let d = dotD * (0.8 + 0.2 * CGFloat(i) / 2)
        ctx.setFillColor(tint(progress(dy), a))
        ctx.fillEllipse(in: CGRect(x: cx - d / 2, y: dy - d / 2, width: d, height: d))
    }
    // Dash
    ctx.setLineWidth(sw * 0.85)
    ctx.setStrokeColor(tint(progress((dashTop + dashBottom) / 2), 1))
    ctx.move(to: CGPoint(x: cx, y: dashTop - sw * 0.42))
    ctx.addLine(to: CGPoint(x: cx, y: dashBottom + sw * 0.42))
    ctx.strokePath()
    // Solid shaft + head as one continuous stroke
    let wing = inner * 0.42
    ctx.setLineWidth(sw)
    ctx.setStrokeColor(tint(1, 1))
    ctx.move(to: CGPoint(x: cx, y: solidTop - sw * 0.5))
    ctx.addLine(to: CGPoint(x: cx, y: tip + sw * 0.5))
    ctx.strokePath()
    ctx.move(to: CGPoint(x: cx - wing, y: tip + wing))
    ctx.addLine(to: CGPoint(x: cx, y: tip))
    ctx.addLine(to: CGPoint(x: cx + wing, y: tip + wing))
    ctx.strokePath()
}

/// Full-color app / extension icon.
func render(size: Int, margin: Bool) -> CGImage {
    let S = CGFloat(size)
    let ctx = makeContext(size)

    // macOS icon grid: ~10% transparent margin, corner radius ≈ 22.37% of the tile.
    let inset = margin ? S * 0.10 : 0
    let tile = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
    let radius = tile.width * 0.2237
    let tilePath = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

    if margin {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.012), blur: S * 0.03,
                      color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
        ctx.addPath(tilePath)
        ctx.setFillColor(CGColor(red: 0.08, green: 0.10, blue: 0.19, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let bg = CGGradient(colorsSpace: srgb, colors: [
        CGColor(red: 0.13, green: 0.16, blue: 0.30, alpha: 1),
        CGColor(red: 0.07, green: 0.09, blue: 0.18, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    let hl = CGGradient(colorsSpace: srgb, colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.10),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(hl, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.midY), options: [])

    // Glyph: blue at the top grading to cyan at the arrowhead; glow pass then core pass.
    let side = tile.width * 0.70
    let box = CGRect(x: tile.midX - side / 2, y: tile.midY - side / 2, width: side, height: side)
    func tint(_ p: CGFloat, _ a: CGFloat) -> CGColor {
        CGColor(red: 0.30 + 0.25 * p, green: 0.65 + 0.30 * p, blue: 1.0, alpha: a)
    }
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: side * 0.06, color: CGColor(red: 0.35, green: 0.80, blue: 1.0, alpha: 0.85))
    drawGlyph(ctx, in: box) { p, a in tint(p, a * 0.6) }
    ctx.restoreGState()
    drawGlyph(ctx, in: box, tint: tint)
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.setLineWidth(max(1, S * 0.008))
    ctx.setStrokeColor(CGColor(red: 0.62, green: 0.66, blue: 0.76, alpha: 0.55))
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

/// Monochrome template image for the menu bar (black on transparent; macOS tints it).
func renderTemplate(size: Int, filled: Bool) -> CGImage {
    let S = CGFloat(size)
    let ctx = makeContext(size)
    let pad = S * 0.04
    let box = CGRect(x: pad, y: pad, width: S - 2 * pad, height: S - 2 * pad)
    if filled {
        // Active state: solid disc with the arrow knocked out.
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fillEllipse(in: box)
        ctx.setBlendMode(.destinationOut)
        drawGlyph(ctx, in: box) { _, a in CGColor(gray: 0, alpha: a) }
    } else {
        drawGlyph(ctx, in: box) { _, a in CGColor(gray: 0, alpha: a) }
    }
    return ctx.makeImage()!
}

func write(_ img: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/icons"
let iconset = out + "/AppIcon.iconset", ext = out + "/ext", menubar = out + "/menubar"
for d in [iconset, ext, menubar] { try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true) }
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)" + (scale == 2 ? "@2x" : "") + ".png"
        write(render(size: base * scale, margin: true), to: iconset + "/" + name)
    }
}
for s in [48, 96, 128] { write(render(size: s, margin: false), to: ext + "/icon\(s).png") }
write(render(size: 1024, margin: true), to: out + "/icon-1024.png")
// Menu bar templates: 18pt @1x/@2x, idle (outline) and active (filled).
for (name, filled) in [("MenuBarIcon", false), ("MenuBarIconActive", true)] {
    write(renderTemplate(size: 18, filled: filled), to: menubar + "/\(name).png")
    write(renderTemplate(size: 36, filled: filled), to: menubar + "/\(name)@2x.png")
}
print("icons -> \(out)")
