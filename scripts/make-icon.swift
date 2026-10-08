// Renders Resources/AppIcon.icns and docs/icon.png. Run: swift scripts/make-icon.swift
//
// A stack of frosted-glass clipboard cards floating over a soft aurora, in the style of
// macOS 26's Liquid Glass icons.
import AppKit
import CoreImage

let size = 1024
let canvas = CGFloat(size)
let space = CGColorSpace(name: CGColorSpace.displayP3)!
let ci = CIContext(options: [.workingColorSpace: space])

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

func context() -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// MARK: Background: deep aurora

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = roundedRect(tile, 186)

let aurora: CGImage = {
    let c = context()
    let base = CGGradient(colorsSpace: space, colors: [
        color(0.07, 0.08, 0.20), color(0.16, 0.10, 0.33), color(0.05, 0.22, 0.36),
    ] as CFArray, locations: [0, 0.55, 1])!
    c.drawLinearGradient(base, start: CGPoint(x: 0, y: canvas), end: CGPoint(x: canvas, y: 0), options: [])
    // Soft glowing blobs that the glass will refract.
    let blobs: [(CGPoint, CGFloat, CGColor)] = [
        (CGPoint(x: 300, y: 760), 420, color(0.55, 0.36, 1.00, 0.95)),
        (CGPoint(x: 780, y: 640), 380, color(0.20, 0.78, 1.00, 0.85)),
        (CGPoint(x: 560, y: 220), 440, color(1.00, 0.42, 0.70, 0.75)),
        (CGPoint(x: 200, y: 260), 300, color(0.25, 0.95, 0.85, 0.55)),
    ]
    for (center, radius, tint) in blobs {
        let glow = CGGradient(colorsSpace: space, colors: [tint, tint.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
        c.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }
    return c.makeImage()!
}()

/// What the background looks like through frosted glass: blurred, brighter and more saturated.
let frosted: CGImage = {
    let input = CIImage(cgImage: aurora).clampedToExtent()
    let blurred = input.applyingGaussianBlur(sigma: 38)
        .applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 1.35, kCIInputBrightnessKey: 0.10,
        ])
        .cropped(to: CGRect(x: 0, y: 0, width: canvas, height: canvas))
    return ci.createCGImage(blurred, from: blurred.extent, format: .RGBA8, colorSpace: space)!
}()

// MARK: Glass card

func glassCard(_ c: CGContext, rect: CGRect, radius: CGFloat, angle: CGFloat, strength: CGFloat) {
    let path = roundedRect(rect, radius)
    c.saveGState()
    c.translateBy(x: rect.midX, y: rect.midY)
    c.rotate(by: angle)
    c.translateBy(x: -rect.midX, y: -rect.midY)

    // Drop shadow beneath the glass.
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -26), blur: 60, color: color(0.02, 0.0, 0.10, 0.55 * strength))
    c.addPath(path)
    c.setFillColor(color(0, 0, 0, 0.25))
    c.fillPath()
    c.restoreGState()

    // Frosted body: refracted background, a milky tint and a top-lit sheen.
    c.saveGState()
    c.addPath(path)
    c.clip()
    c.draw(frosted, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
    c.setFillColor(color(1, 1, 1, 0.16 * strength))
    c.fill(rect.insetBy(dx: -40, dy: -40))
    let sheen = CGGradient(colorsSpace: space, colors: [
        color(1, 1, 1, 0.42 * strength), color(1, 1, 1, 0.06), color(1, 1, 1, 0.0),
    ] as CFArray, locations: [0, 0.45, 1])!
    c.drawLinearGradient(sheen, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    c.restoreGState()

    // Specular rim: bright on the top edge, fading down the sides.
    c.saveGState()
    c.addPath(path)
    c.setLineWidth(5)
    c.replacePathWithStrokedPath()
    c.clip()
    let rim = CGGradient(colorsSpace: space, colors: [
        color(1, 1, 1, 0.95), color(1, 1, 1, 0.18), color(1, 1, 1, 0.45),
    ] as CFArray, locations: [0, 0.6, 1])!
    c.drawLinearGradient(rim, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    c.restoreGState()
    c.restoreGState()
}

// MARK: Compose

let c = context()

// The tile itself, with a soft shadow on the desktop.
c.saveGState()
c.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(0, 0, 0, 0.35))
c.addPath(tilePath)
c.setFillColor(color(0.08, 0.06, 0.2))
c.fillPath()
c.restoreGState()

c.saveGState()
c.addPath(tilePath)
c.clip()
c.draw(aurora, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))

// History: a card tilted behind the main one.
glassCard(c, rect: CGRect(x: 318, y: 252, width: 420, height: 520), radius: 70, angle: 0.16, strength: 0.7)
// Main clipboard card.
let card = CGRect(x: 286, y: 214, width: 452, height: 552)
glassCard(c, rect: card, radius: 76, angle: -0.04, strength: 1)

// Content on the main card: the clip and three lines of text.
c.translateBy(x: card.midX, y: card.midY)
c.rotate(by: -0.04)
c.translateBy(x: -card.midX, y: -card.midY)

let clip = CGRect(x: card.midX - 92, y: card.maxY - 52, width: 184, height: 92)
c.saveGState()
c.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0.05, 0, 0.2, 0.45))
c.addPath(roundedRect(clip, 40))
let clipFill = CGGradient(colorsSpace: space, colors: [color(1, 1, 1, 1), color(0.86, 0.88, 1, 1)] as CFArray, locations: [0, 1])!
c.clip()
c.drawLinearGradient(clipFill, start: CGPoint(x: clip.midX, y: clip.maxY), end: CGPoint(x: clip.midX, y: clip.minY), options: [])
c.restoreGState()
c.addPath(roundedRect(CGRect(x: clip.midX - 34, y: clip.midY - 4, width: 68, height: 22), 11))
c.setFillColor(color(0.36, 0.30, 0.70, 0.55))
c.fillPath()

for (index, width) in [300.0, 236, 268].enumerated() {
    let line = CGRect(x: card.minX + 76, y: card.maxY - 196 - CGFloat(index) * 92, width: width, height: 34)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -3), blur: 8, color: color(0.1, 0, 0.3, 0.35))
    c.addPath(roundedRect(line, 17))
    c.setFillColor(color(1, 1, 1, index == 0 ? 0.96 : 0.78))
    c.fillPath()
    c.restoreGState()
}
c.restoreGState()

// Glassy edge of the tile.
c.saveGState()
c.addPath(roundedRect(tile.insetBy(dx: 2, dy: 2), 184))
c.setLineWidth(4)
c.replacePathWithStrokedPath()
c.clip()
let edge = CGGradient(colorsSpace: space, colors: [color(1, 1, 1, 0.55), color(1, 1, 1, 0.05), color(1, 1, 1, 0.22)] as CFArray,
                      locations: [0, 0.5, 1])!
c.drawLinearGradient(edge, start: CGPoint(x: canvas / 2, y: tile.maxY), end: CGPoint(x: canvas / 2, y: tile.minY), options: [])
c.restoreGState()

let master = c.makeImage()!

// MARK: Export

func png(_ image: CGImage, side: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    g.imageInterpolation = .high
    NSGraphicsContext.current = g
    g.cgContext.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! png(master, side: base * scale).write(to: iconset.appending(path: name))
    }
}
try! png(master, side: 512).write(to: URL(fileURLWithPath: "docs/icon.png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
print("wrote Resources/AppIcon.icns and docs/icon.png")
