import AppKit
let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform(); transform.scale(by: factor); transform.concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 198, yRadius: 198)
        NSGradient(starting: NSColor(srgbRed: 0.13, green: 0.48, blue: 0.40, alpha: 1), ending: NSColor(srgbRed: 0.04, green: 0.24, blue: 0.23, alpha: 1))!.draw(in: background, angle: -70)
        NSColor(srgbRed: 0.87, green: 0.98, blue: 0.90, alpha: 1).setStroke()
        let corners = NSBezierPath(); corners.lineWidth = 40; corners.lineCapStyle = .round; corners.lineJoinStyle = .round
        for (x, y, dx, dy) in [(300.0, 724.0, 1.0, -1.0), (724, 724, -1, -1), (300, 300, 1, 1), (724, 300, -1, 1)] {
            corners.move(to: NSPoint(x: x + dx * 96, y: y)); corners.line(to: NSPoint(x: x, y: y)); corners.line(to: NSPoint(x: x, y: y + dy * 96))
        }
        corners.stroke()
        let check = NSBezierPath(); check.lineWidth = 44; check.lineCapStyle = .round; check.lineJoinStyle = .round
        check.move(to: NSPoint(x: 414, y: 514)); check.line(to: NSPoint(x: 483, y: 447)); check.line(to: NSPoint(x: 619, y: 585)); check.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(destination)/icon_\(size)x\(size)\(suffix).png"))
    }
}
