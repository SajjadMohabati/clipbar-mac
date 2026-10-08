// Renders Resources/dmg-background.tiff, the backdrop of the installer window.
// Run: swift scripts/make-dmg-background.swift
import AppKit

let width: CGFloat = 660, height: CGFloat = 400

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let bounds = NSRect(x: 0, y: 0, width: width, height: height)

    // The icon's aurora as a light pastel wash: Finder always draws icon labels in black.
    NSGradient(colors: [
        NSColor(srgbRed: 0.96, green: 0.95, blue: 1.0, alpha: 1),
        NSColor(srgbRed: 0.93, green: 0.95, blue: 1.0, alpha: 1),
        NSColor(srgbRed: 0.92, green: 0.98, blue: 1.0, alpha: 1),
    ])!.draw(in: bounds, angle: -30)
    for (x, y, r, tint) in [
        (110.0, 340.0, 280.0, NSColor(srgbRed: 0.72, green: 0.6, blue: 1, alpha: 0.45)),
        (570, 320, 260, NSColor(srgbRed: 0.5, green: 0.86, blue: 1, alpha: 0.45)),
        (380, 20, 300, NSColor(srgbRed: 1, green: 0.66, blue: 0.84, alpha: 0.38)),
    ] {
        NSGradient(colors: [tint, tint.withAlphaComponent(0)])!
            .draw(fromCenter: NSPoint(x: x, y: y), radius: 0, toCenter: NSPoint(x: x, y: y), radius: r, options: [])
    }

    func text(_ string: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, y: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor(srgbRed: 0.1, green: 0.09, blue: 0.22, alpha: alpha),
            .paragraphStyle: style,
        ]
        string.draw(in: NSRect(x: 0, y: y, width: width, height: size * 1.5), withAttributes: attributes)
    }

    text("Install ClipBar", size: 24, weight: .bold, alpha: 0.95, y: 330)
    text("Drag the app onto Applications", size: 13, weight: .medium, alpha: 0.6, y: 306)

    // Frosted glass shelves under the two icons, joined by an arrow.
    for x in [180.0, 480.0] {
        let shelf = NSBezierPath(roundedRect: NSRect(x: x - 92, y: 100, width: 184, height: 196), xRadius: 42, yRadius: 42)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(srgbRed: 0.25, green: 0.2, blue: 0.5, alpha: 0.12)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.set()
        NSColor.white.withAlphaComponent(0.45).setFill()
        shelf.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(colors: [.white.withAlphaComponent(0.5), .white.withAlphaComponent(0.1)])!
            .draw(in: shelf, angle: -90)
        NSColor.white.withAlphaComponent(0.9).setStroke()
        shelf.lineWidth = 1
        shelf.stroke()
    }
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 284, y: 210))
    arrow.line(to: NSPoint(x: 370, y: 210))
    arrow.move(to: NSPoint(x: 356, y: 222))
    arrow.line(to: NSPoint(x: 372, y: 210))
    arrow.line(to: NSPoint(x: 356, y: 198))
    arrow.lineWidth = 3.5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    NSColor(srgbRed: 0.35, green: 0.3, blue: 0.6, alpha: 0.6).setStroke()
    arrow.stroke()

    text("Created by Sajjad Mohabati", size: 12, weight: .semibold, alpha: 0.75, y: 62)
    text("github.com/SajjadMohabati/clipbar-mac", size: 11, weight: .regular, alpha: 0.5, y: 44)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let image = NSImage(size: NSSize(width: width, height: height))
image.addRepresentation(render(scale: 1))
image.addRepresentation(render(scale: 2))
try! image.tiffRepresentation(using: .lzw, factor: 0)!.write(to: URL(fileURLWithPath: "Resources/dmg-background.tiff"))
print("wrote Resources/dmg-background.tiff")
