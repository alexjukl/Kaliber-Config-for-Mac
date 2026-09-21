import AppKit
// App icon: dark rounded square, a conic RGB colour wheel ring, "KG" in the centre. Writes AppIcon.icns next to this script.
let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iconset = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : dir.path).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext
    let s = CGFloat(px)
    // background squircle
    let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.05, dy: s * 0.05), xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(colors: [NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.20, alpha: 1), NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.07, alpha: 1)])!.draw(in: bg, angle: -90)
    // colour wheel ring (conic gradient) clipped to an annulus
    let c = CGPoint(x: s / 2, y: s / 2)
    let outer = s * 0.40, inner = s * 0.255
    ctx.saveGState()
    let ring = CGMutablePath()
    ring.addEllipse(in: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2))
    ring.addEllipse(in: CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2))
    ctx.addPath(ring); ctx.clip(using: .evenOdd)
    let steps = 360
    for i in 0..<steps {
        let a0 = CGFloat(i) / CGFloat(steps) * 2 * .pi, a1 = (CGFloat(i) + 1.5) / CGFloat(steps) * 2 * .pi
        let p = CGMutablePath(); p.move(to: c)
        p.addArc(center: c, radius: outer + 2, startAngle: a0, endAngle: a1, clockwise: false); p.closeSubpath()
        ctx.addPath(p)
        ctx.setFillColor(NSColor(calibratedHue: CGFloat(i) / CGFloat(steps), saturation: 0.95, brightness: 1, alpha: 1).cgColor)
        ctx.fillPath()
    }
    // soft inner/outer shading on the ring
    ctx.setBlendMode(.multiply)
    let shade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor(white: 0.55, alpha: 1).cgColor, NSColor.white.cgColor, NSColor.white.cgColor, NSColor(white: 0.6, alpha: 1).cgColor] as CFArray, locations: [0, 0.25, 0.8, 1])!
    ctx.drawRadialGradient(shade, startCenter: c, startRadius: inner, endCenter: c, endRadius: outer, options: [])
    ctx.restoreGState()
    // inner disc
    ctx.saveGState()
    let disc = CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2)
    ctx.addEllipse(in: disc); ctx.clip()
    let discGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor(calibratedRed: 0.20, green: 0.20, blue: 0.25, alpha: 1).cgColor, NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.08, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(discGrad, start: CGPoint(x: c.x, y: c.y + inner), end: CGPoint(x: c.x, y: c.y - inner), options: [])
    ctx.restoreGState()
    // "KG"
    let font = NSFont.systemFont(ofSize: s * 0.30, weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white,
        .shadow: { let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.6); sh.shadowBlurRadius = s * 0.02; sh.shadowOffset = NSSize(width: 0, height: -s * 0.01); return sh }(),
        .kern: -s * 0.012]
    let str = NSAttributedString(string: "KG", attributes: attrs)
    let size = str.size()
    str.draw(at: NSPoint(x: c.x - size.width / 2, y: c.y - size.height / 2 + s * 0.005))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let rep = render(px)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
// also a preview PNG
try! render(512).representation(using: .png, properties: [:])!.write(to: iconset.deletingLastPathComponent().appendingPathComponent("AppIcon-preview.png"))
print("iconset written to", iconset.path)
