// Draws the installer window background: swift scripts/dmg/make_background.swift <output-dir>
// Writes background.png (660×420) and background@2x.png (1320×840).
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let W: CGFloat = 660, H: CGFloat = 420

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    func y(_ top: CGFloat) -> CGFloat { H - top }  // design in top-left coordinates
    func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    // ground: Downer's dark ink with its ember / violet glows
    color(0.055, 0.04, 0.05).setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()
    func glow(_ c: NSColor, at p: CGPoint, radius: CGFloat) {
        NSGradient(colors: [c, c.withAlphaComponent(0)])!
            .draw(fromCenter: p, radius: 0, toCenter: p, radius: radius, options: [])
    }
    glow(color(0.94, 0.22, 0.29, 0.55), at: CGPoint(x: 560, y: y(20)), radius: 380)
    glow(color(0.34, 0.23, 0.75, 0.40), at: CGPoint(x: 0, y: y(260)), radius: 330)
    glow(color(0.84, 0.16, 0.34, 0.42), at: CGPoint(x: 600, y: y(430)), radius: 360)

    // title and instruction
    func text(_ s: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, centerY top: CGFloat) {
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
            .paragraphStyle: style,
        ]
        let h = size * 1.4
        (s as NSString).draw(in: NSRect(x: 0, y: y(top) - h / 2, width: W, height: h), withAttributes: attrs)
    }
    text("Install Downer", size: 27, weight: .semibold, alpha: 0.96, centerY: 46)
    text("Drag Downer into your Applications folder", size: 14.5, weight: .regular, alpha: 0.66, centerY: 76)

    // label pills: Finder draws icon labels in black, so they get a light frosted backing
    for cx in [CGFloat(170), 490] {
        let r = NSRect(x: cx - 70, y: y(268) - 13, width: 140, height: 26)
        let path = NSBezierPath(roundedRect: r, xRadius: 13, yRadius: 13)
        color(0.93, 0.92, 0.94, 0.90).setFill(); path.fill()
        NSColor.white.withAlphaComponent(0.55).setStroke(); path.lineWidth = 1; path.stroke()
    }

    // the arrow from the app to Applications
    let red1 = color(1.0, 0.33, 0.41), red2 = color(0.85, 0.13, 0.24)
    let ay = y(185)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 14, color: red1.withAlphaComponent(0.55).cgColor)
    let shaft = NSBezierPath()
    shaft.move(to: CGPoint(x: 268, y: ay)); shaft.line(to: CGPoint(x: 392, y: ay))
    shaft.lineWidth = 7; shaft.lineCapStyle = .round
    red1.setStroke(); shaft.stroke()
    let head = NSBezierPath()
    head.move(to: CGPoint(x: 374, y: ay + 20)); head.line(to: CGPoint(x: 396, y: ay)); head.line(to: CGPoint(x: 374, y: ay - 20))
    head.lineWidth = 7; head.lineCapStyle = .round; head.lineJoinStyle = .round
    red2.setStroke(); head.stroke()
    ctx.restoreGState()

    text("macOS blocks the first launch? The install steps are in the README.", size: 11.5, weight: .regular, alpha: 0.42, centerY: 318)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (scale, name) in [(1.0, "background.png"), (2.0, "background@2x.png")] {
    let rep = render(scale: CGFloat(scale))
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
print("wrote backgrounds to \(outDir)")
