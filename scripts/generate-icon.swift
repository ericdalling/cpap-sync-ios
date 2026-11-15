import AppKit

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    NSColor(srgbRed: 0.12, green: 0.32, blue: 0.75, alpha: 1).setFill()
    rect.fill()
    let center = NSPoint(x: 512, y: 512)
    NSColor.white.setStroke()
    for start in [CGFloat(25), CGFloat(205)] {
        let path = NSBezierPath()
        path.lineWidth = 62
        path.lineCapStyle = .round
        path.appendArc(withCenter: center, radius: 250, startAngle: start, endAngle: start + 135)
        path.stroke()
    }
    NSColor.white.setFill()
    for angle in [CGFloat(160), CGFloat(340)] {
        let radians = angle * .pi / 180
        let p = NSPoint(x: center.x + 250 * cos(radians), y: center.y + 250 * sin(radians))
        let tangent = NSPoint(x: -sin(radians), y: cos(radians))
        let radial = NSPoint(x: cos(radians), y: sin(radians))
        let tip = NSPoint(x: p.x + tangent.x * 90, y: p.y + tangent.y * 90)
        let arrow = NSBezierPath()
        arrow.move(to: tip)
        arrow.line(to: NSPoint(x: p.x - tangent.x * 60 + radial.x * 85, y: p.y - tangent.y * 60 + radial.y * 85))
        arrow.line(to: NSPoint(x: p.x - tangent.x * 60 - radial.x * 85, y: p.y - tangent.y * 60 - radial.y * 85))
        arrow.close()
        arrow.fill()
    }
    return true
}
guard let tiff = image.tiffRepresentation, let source = NSBitmapImageRep(data: tiff),
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("Cannot render icon") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
source.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
try png.write(to: URL(fileURLWithPath: "CPAPSync/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
