import AppKit

// Stash for Mac icon: deep green tile, a white safe door with a dial, and a small key.
func draw(_ s: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let inset = s * 0.06
    let tile = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset), xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(colors: [NSColor(calibratedRed: 0.24, green: 0.66, blue: 0.48, alpha: 1),
                        NSColor(calibratedRed: 0.08, green: 0.40, blue: 0.30, alpha: 1)])!.draw(in: tile, angle: -70)
    // safe door
    let door = NSRect(x: s * 0.20, y: s * 0.20, width: s * 0.60, height: s * 0.60)
    NSColor.white.withAlphaComponent(0.96).setFill()
    NSBezierPath(roundedRect: door, xRadius: s * 0.08, yRadius: s * 0.08).fill()
    NSColor(calibratedRed: 0.85, green: 0.90, blue: 0.88, alpha: 1).setFill()
    NSBezierPath(roundedRect: door.insetBy(dx: s * 0.05, dy: s * 0.05), xRadius: s * 0.05, yRadius: s * 0.05).fill()
    // dial
    let c = NSPoint(x: s * 0.50, y: s * 0.50), r = s * 0.14
    NSColor(calibratedRed: 0.08, green: 0.40, blue: 0.30, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).fill()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - r * 0.62, y: c.y - r * 0.62, width: r * 1.24, height: r * 1.24)).fill()
    NSColor(calibratedRed: 0.08, green: 0.40, blue: 0.30, alpha: 1).setStroke()
    for i in 0..<12 {
        let a = CGFloat(i) * .pi / 6
        let tick = NSBezierPath()
        tick.move(to: NSPoint(x: c.x + cos(a) * r * 0.70, y: c.y + sin(a) * r * 0.70))
        tick.line(to: NSPoint(x: c.x + cos(a) * r * 0.92, y: c.y + sin(a) * r * 0.92))
        tick.lineWidth = s * 0.012; tick.stroke()
    }
    let pointer = NSBezierPath()
    pointer.move(to: c); pointer.line(to: NSPoint(x: c.x + r * 0.55, y: c.y + r * 0.35)); pointer.lineWidth = s * 0.02; pointer.lineCapStyle = .round; pointer.stroke()
    // handle
    NSColor(calibratedRed: 0.08, green: 0.40, blue: 0.30, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.70, y: s * 0.42, width: s * 0.05, height: s * 0.16), xRadius: s * 0.02, yRadius: s * 0.02).fill()
    // key, bottom-left
    let gold = NSColor(calibratedRed: 0.98, green: 0.80, blue: 0.25, alpha: 1)
    gold.setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.13, y: s * 0.13, width: s * 0.12, height: s * 0.12)).fill()
    NSColor(calibratedRed: 0.08, green: 0.40, blue: 0.30, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.165, y: s * 0.165, width: s * 0.05, height: s * 0.05)).fill()
    gold.setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.23, y: s * 0.175, width: s * 0.16, height: s * 0.035), xRadius: s * 0.01, yRadius: s * 0.01).fill()
    NSBezierPath(rect: NSRect(x: s * 0.33, y: s * 0.15, width: s * 0.025, height: s * 0.04)).fill()
    NSBezierPath(rect: NSRect(x: s * 0.365, y: s * 0.15, width: s * 0.025, height: s * 0.05)).fill()
    img.unlockFocus()
    return img
}

let out = "icon/StashMac.iconset"
try? FileManager.default.removeItem(atPath: out)
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),("128x128@2x",256),
                   ("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
    let img = draw(CGFloat(px))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
print("iconset written")
