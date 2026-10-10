// MC Download Manager icon generator (CoreGraphics).
// Renders "parallel streams": dots converging into glowing lines forming a downward arrow.
// Usage: swiftc -O scripts/make_icons.swift -o build/make_icons && build/make_icons <out_dir>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func render(size: Int, margin: Bool) -> CGImage {
    let S = CGFloat(size)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // macOS icon grid: ~10% transparent margin, corner radius ≈ 22.37% of the tile.
    let inset = margin ? S * 0.10 : 0
    let tile = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
    let radius = tile.width * 0.2237
    let tilePath = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow under the tile
    if margin {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.012), blur: S * 0.03,
                      color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
        ctx.addPath(tilePath)
        ctx.setFillColor(CGColor(red: 0.08, green: 0.10, blue: 0.19, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Background gradient (navy)
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let bg = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0.13, green: 0.16, blue: 0.30, alpha: 1),
        CGColor(red: 0.07, green: 0.09, blue: 0.18, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    // Subtle vignette highlight at top
    let hl = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.10),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(hl, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.midY), options: [])

    // Streams
    let columns = 11
    let cx = tile.midX
    let spacing = tile.width * 0.058
    let lineW = max(1.5, tile.width * 0.022)
    let dotH = lineW * 1.9
    let dotGap = tile.height * 0.075
    let topY = tile.maxY - tile.height * 0.16           // first dot row (CG: y up)
    let dotRows = 4
    let lineTop = topY - CGFloat(dotRows) * dotGap       // where the solid line starts
    let minLen = tile.height * 0.22                      // outer column line length
    let maxLen = tile.height * 0.46                      // center column line length

    func color(for col: Int, alpha: CGFloat) -> CGColor {
        let d = abs(CGFloat(col - columns / 2)) / CGFloat(columns / 2)   // 0 center … 1 edge
        // center: cyan (0.45,0.95,1.0)  edge: blue (0.20,0.55,1.0)
        return CGColor(red: 0.45 - 0.25 * d, green: 0.95 - 0.40 * d, blue: 1.0, alpha: alpha)
    }

    for pass in 0..<2 {   // pass 0: glow, pass 1: core
        for col in 0..<columns {
            let x = cx + CGFloat(col - columns / 2) * spacing
            let d = abs(CGFloat(col - columns / 2)) / CGFloat(columns / 2)
            let len = maxLen - (maxLen - minLen) * pow(d, 1.15)
            ctx.saveGState()
            if pass == 0 {
                ctx.setShadow(offset: .zero, blur: lineW * 2.6, color: color(for: col, alpha: 0.9))
                ctx.setFillColor(color(for: col, alpha: 0.55))
            } else {
                ctx.setFillColor(color(for: col, alpha: 1))
            }
            // dots (fade in from top)
            for r in 0..<dotRows {
                let y = topY - CGFloat(r) * dotGap
                let a: CGFloat = 0.45 + 0.55 * CGFloat(r) / CGFloat(dotRows - 1)
                let h = dotH * (0.75 + 0.25 * CGFloat(r) / CGFloat(dotRows - 1))
                let rect = CGRect(x: x - lineW / 2, y: y - h / 2, width: lineW, height: h)
                ctx.setFillColor(color(for: col, alpha: pass == 0 ? 0.35 * a : a))
                ctx.addPath(CGPath(roundedRect: rect, cornerWidth: lineW / 2, cornerHeight: lineW / 2, transform: nil))
                ctx.fillPath()
            }
            // solid line
            let rect = CGRect(x: x - lineW / 2, y: lineTop - len, width: lineW, height: len)
            ctx.setFillColor(color(for: col, alpha: pass == 0 ? 0.55 : 1))
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: lineW / 2, cornerHeight: lineW / 2, transform: nil))
            ctx.fillPath()
            ctx.restoreGState()
        }
    }
    ctx.restoreGState()

    // Border (light rim)
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.setLineWidth(max(1, S * 0.008))
    ctx.setStrokeColor(CGColor(red: 0.62, green: 0.66, blue: 0.76, alpha: 0.55))
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

func write(_ img: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/icons"
let iconset = out + "/AppIcon.iconset", ext = out + "/ext"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(atPath: ext, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)" + (scale == 2 ? "@2x" : "") + ".png"
        write(render(size: base * scale, margin: true), to: iconset + "/" + name)
    }
}
for s in [48, 96, 128] { write(render(size: s, margin: false), to: ext + "/icon\(s).png") }
write(render(size: 1024, margin: true), to: out + "/icon-1024.png")
print("icons -> \(out)")
