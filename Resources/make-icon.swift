// Renders the app icon (all macOS sizes) into Resources/AppIcon.iconset, then build with:
//   swift Resources/make-icon.swift && iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)

    func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: a)
    }

    // macOS icon grid: 824 × 824 squircle centred on 1024 canvas
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.45))
    ctx.addPath(tilePath); ctx.setFillColor(color(0x1B1B1D)); ctx.fillPath()
    ctx.restoreGState()

    // graphite gradient
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0x34343A), color(0x121214)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // soft top sheen
    ctx.setFillColor(color(0xFFFFFF, 0.05))
    ctx.fillEllipse(in: CGRect(x: 40, y: 600, width: 944, height: 520))
    ctx.restoreGState()
    ctx.addPath(tilePath); ctx.setStrokeColor(color(0xFFFFFF, 0.08)); ctx.setLineWidth(3); ctx.strokePath()

    // tablet body
    let body = CGRect(x: 196, y: 300, width: 632, height: 424)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 46, cornerHeight: 46, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.55))
    ctx.addPath(bodyPath); ctx.setFillColor(color(0x0A0A0B)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(bodyPath); ctx.setStrokeColor(color(0x4A4A50)); ctx.setLineWidth(4); ctx.strokePath()

    // express keys
    ctx.setFillColor(color(0x26262B))
    for y in [640.0, 598.0, 426.0, 384.0] {
        ctx.addPath(CGPath(roundedRect: CGRect(x: 226, y: y, width: 66, height: 30), cornerWidth: 7, cornerHeight: 7, transform: nil))
        ctx.fillPath()
    }
    // touch ring (accent) + centre button
    let ringC = CGPoint(x: 259, y: 512)
    ctx.setStrokeColor(color(0x3D86FF)); ctx.setLineWidth(12)
    ctx.strokeEllipse(in: CGRect(x: ringC.x - 44, y: ringC.y - 44, width: 88, height: 88))
    ctx.setFillColor(color(0x1D1D21))
    ctx.fillEllipse(in: CGRect(x: ringC.x - 18, y: ringC.y - 18, width: 36, height: 36))
    // lit LED
    ctx.setShadow(offset: .zero, blur: 14, color: color(0x9CC3FF, 0.9))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: ringC.x + 46, y: ringC.y + 40, width: 12, height: 12))
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // active area + glowing corner marks
    let area = CGRect(x: 336, y: 344, width: 452, height: 336)
    ctx.addPath(CGPath(roundedRect: area, cornerWidth: 14, cornerHeight: 14, transform: nil))
    ctx.setFillColor(color(0x141417)); ctx.fillPath()
    ctx.setStrokeColor(color(0xFFFFFF, 0.85)); ctx.setLineWidth(6); ctx.setLineCap(.round)
    let m: CGFloat = 22, l: CGFloat = 38
    for (cx, cy, dx, dy) in [(area.minX + m, area.maxY - m, 1.0, -1.0), (area.maxX - m, area.maxY - m, -1.0, -1.0),
                             (area.minX + m, area.minY + m, 1.0, 1.0), (area.maxX - m, area.minY + m, -1.0, 1.0)] {
        ctx.move(to: CGPoint(x: cx, y: cy + dy * l)); ctx.addLine(to: CGPoint(x: cx, y: cy)); ctx.addLine(to: CGPoint(x: cx + dx * l, y: cy))
    }
    ctx.strokePath()

    // pen stroke: a smooth accent curve, thin → thick → thin (pressure)
    let pts: [CGPoint] = (0...60).map { i in
        let t = CGFloat(i) / 60
        return CGPoint(x: 392 + t * 340, y: 470 + sin(t * .pi * 1.6) * 70 + t * 40)
    }
    for i in 1..<pts.count {
        let t = CGFloat(i) / CGFloat(pts.count)
        ctx.setStrokeColor(color(0x3D86FF))
        ctx.setLineWidth(4 + sin(t * .pi) * 18)
        ctx.move(to: pts[i - 1]); ctx.addLine(to: pts[i]); ctx.strokePath()
    }

    // pen
    ctx.saveGState()
    ctx.translateBy(x: 742, y: 520)
    ctx.rotate(by: -.pi / 4.6)
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0x000000, 0.6))
    let barrel = CGPath(roundedRect: CGRect(x: -26, y: 0, width: 52, height: 270), cornerWidth: 26, cornerHeight: 26, transform: nil)
    ctx.addPath(barrel)
    ctx.setFillColor(color(0xE9E9EE)); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    // grip
    ctx.setFillColor(color(0x2A2A2F))
    ctx.addPath(CGPath(roundedRect: CGRect(x: -26, y: 40, width: 52, height: 120), cornerWidth: 20, cornerHeight: 20, transform: nil)); ctx.fillPath()
    ctx.setFillColor(color(0x3D86FF))
    ctx.fill(CGRect(x: -26, y: 168, width: 52, height: 8))
    // nib cone
    ctx.setFillColor(color(0xC9C9D0))
    ctx.move(to: CGPoint(x: -24, y: 6)); ctx.addLine(to: CGPoint(x: 24, y: 6)); ctx.addLine(to: CGPoint(x: 5, y: -46)); ctx.addLine(to: CGPoint(x: -5, y: -46)); ctx.closePath(); ctx.fillPath()
    ctx.setFillColor(color(0x1B1B1D))
    ctx.fill(CGRect(x: -4, y: -58, width: 8, height: 14))
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.iconset")
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    let data = render(px).representation(using: .png, properties: [:])!
    try! data.write(to: dir.appendingPathComponent("icon_\(name).png"))
}
print("ok")
