// Draws the app icon in liquid glass: a warm amber tile, a frosted sheet
// of clear glass on it, and three checklist rows, rings and glass bars,
// the first ring filled and checked. swift icon.swift out.png
import AppKit

let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
    func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
    }
    let white = { (a: CGFloat) in NSColor(white: 1, alpha: a) }
    let ctx = NSGraphicsContext.current!.cgContext
    // fill paints a top-to-bottom gradient into path (angle 90 is down, flipped)
    func fill(_ path: NSBezierPath, _ top: NSColor, _ bottom: NSColor) { NSGradient(starting: top, ending: bottom)!.draw(in: path, angle: 90) }
    // rim strokes path lit from the upper left, with a fainter catch light
    // on the lower right: the two bright edges of liquid glass
    func rim(_ path: NSBezierPath, _ width: CGFloat, _ a: CGFloat = 1) {
        ctx.saveGState()
        ctx.addPath(path.cgPath); ctx.setLineWidth(width); ctx.replacePathWithStrokedPath(); ctx.clip()
        NSGradient(colors: [white(0.95 * a), white(0.12 * a), white(0.04 * a), white(0.6 * a)], atLocations: [0, 0.45, 0.6, 1], colorSpace: .sRGB)!
            .draw(in: path.bounds.insetBy(dx: -width, dy: -width), angle: 50)
        ctx.restoreGState()
    }
    // glow lights path from inside its edge, as thick glass does
    func glow(_ path: NSBezierPath, _ blur: CGFloat, _ c: NSColor) {
        ctx.saveGState()
        path.addClip()
        ctx.setShadow(offset: .zero, blur: blur, color: c.cgColor)
        let ring = NSBezierPath(rect: path.bounds.insetBy(dx: -200, dy: -200))
        ring.append(path); ring.windingRule = .evenOdd
        NSColor.black.setFill(); ring.fill()
        ctx.restoreGState()
    }
    func shadow(_ a: CGFloat, _ blur: CGFloat, _ y: CGFloat, _ draw: () -> Void) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -y), blur: blur, color: NSColor(white: 0, alpha: a).cgColor) // CG's y is up
        draw()
        ctx.restoreGState()
    }

    // macOS icon grid: an 824pt rounded square centred in 1024
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    shadow(0.25, 36, 12) { color(0xc2410c).setFill(); tile.fill() }
    fill(tile, color(0xffc15e), color(0xf0660f))
    glow(tile, 60, white(0.35))
    rim(tile, 7, 0.9)

    // the sheet: frosted clear glass, tilted a touch
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 512); ctx.rotate(by: -0.05); ctx.translateBy(x: -512, y: -512)
    let sheet = NSBezierPath(roundedRect: NSRect(x: 222, y: 210, width: 580, height: 604), xRadius: 70, yRadius: 70)
    shadow(0.18, 44, 24) { color(0xffffff, 0.3).setFill(); sheet.fill() }
    fill(sheet, white(0.85), white(0.66))
    glow(sheet, 30, white(0.7))
    rim(sheet, 5)

    for (i, (y, w)) in [(352.0, 330.0), (512.0, 270.0), (672.0, 200.0)].enumerated() {
        // the bar: amber glass with a sheen on top
        let bar = NSBezierPath(roundedRect: NSRect(x: 412, y: y - 30, width: w, height: 60), xRadius: 30, yRadius: 30)
        fill(bar, color(0xffb36b, 0.85), color(0xf08a3c, 0.85))
        rim(bar, 3, 0.7)
        // the checkbox: a ring, the first one filled and checked
        let o = NSRect(x: 296, y: y - 44, width: 88, height: 88)
        let ring = NSBezierPath(ovalIn: o)
        if i == 0 {
            ctx.saveGState(); ctx.setShadow(offset: .zero, blur: 40, color: color(0xffffff, 0.8).cgColor)
            fill(ring, color(0xff8a3d), color(0xd9480f)); ctx.restoreGState()
            rim(ring, 4)
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: o.midX - 22, y: y + 2)); tick.line(to: NSPoint(x: o.midX - 4, y: y + 20)); tick.line(to: NSPoint(x: o.midX + 24, y: y - 16))
            tick.lineWidth = 13; tick.lineCapStyle = .round; tick.lineJoinStyle = .round
            white(1).setStroke(); tick.stroke()
        } else {
            ring.lineWidth = 11; color(0xf08a3c).setStroke(); ring.stroke()
        }
    }
    ctx.restoreGState()
    return true
}
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
