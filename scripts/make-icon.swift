// Renders the DeepCleaner app icon and packages it as Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift
//
// Design: macOS-style rounded-square tile with a teal→blue gradient, a white storage gauge
// ring that's mostly "freed", and a sparkle in the middle.
import AppKit

let canvas: CGFloat = 1024

func renderIcon() -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Tile: 824pt body on the 1024 grid, per Apple's macOS icon template.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tile = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(tile)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    let colors = [
        NSColor(red: 0.20, green: 0.86, blue: 0.78, alpha: 1).cgColor,
        NSColor(red: 0.13, green: 0.52, blue: 0.98, alpha: 1).cgColor,
        NSColor(red: 0.27, green: 0.25, blue: 0.85, alpha: 1).cgColor,
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])

    // Soft glow behind the gauge.
    let glow = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [NSColor.white.withAlphaComponent(0.28).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
        locations: [0, 1]
    )!
    let center = CGPoint(x: canvas / 2, y: canvas / 2)
    ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: 380, options: [])
    ctx.restoreGState()

    // Gauge ring: faint full track, bright arc covering most of it.
    let radius: CGFloat = 282
    let lineWidth: CGFloat = 64
    ctx.setLineCap(.round)
    ctx.setLineWidth(lineWidth)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.22).cgColor)
    ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: NSColor.black.withAlphaComponent(0.18).cgColor)
    ctx.setStrokeColor(NSColor.white.cgColor)
    let start = CGFloat.pi / 2
    ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: start - .pi * 1.45, clockwise: true)
    ctx.strokePath()
    ctx.restoreGState()

    // Sparkles: one large four-point star in the centre, one small accent.
    func sparkle(at point: CGPoint, size: CGFloat, pinch: CGFloat = 0.18) -> CGPath {
        let path = CGMutablePath()
        let r = size / 2
        let tips = [CGPoint(x: 0, y: r), CGPoint(x: r, y: 0), CGPoint(x: 0, y: -r), CGPoint(x: -r, y: 0)]
        path.move(to: CGPoint(x: point.x + tips[0].x, y: point.y + tips[0].y))
        for i in 0..<4 {
            let next = tips[(i + 1) % 4]
            let mid = CGPoint(x: (tips[i].x + next.x) * pinch, y: (tips[i].y + next.y) * pinch)
            path.addQuadCurve(
                to: CGPoint(x: point.x + next.x, y: point.y + next.y),
                control: CGPoint(x: point.x + mid.x, y: point.y + mid.y)
            )
        }
        path.closeSubpath()
        return path
    }

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: NSColor.black.withAlphaComponent(0.2).cgColor)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(sparkle(at: center, size: 300))
    ctx.fillPath()
    ctx.addPath(sparkle(at: CGPoint(x: center.x + 128, y: center.y + 122), size: 96))
    ctx.fillPath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let fm = FileManager.default
let work = fm.temporaryDirectory.appendingPathComponent("deepcleaner-icon-\(UUID().uuidString)")
let iconset = work.appendingPathComponent("AppIcon.iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: work) }

let master = work.appendingPathComponent("icon_1024.png")
try renderIcon().write(to: master)
try? fm.removeItem(at: root.appendingPathComponent("Resources/AppIcon.png"))
try fm.copyItem(at: master, to: root.appendingPathComponent("Resources/AppIcon.png"))

func run(_ tool: String, _ args: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = args
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CocoaError(.executableLoad) }
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try run("/usr/bin/sips", ["-z", "\(pixels)", "\(pixels)", master.path, "--out", iconset.appendingPathComponent(name).path])
    }
}
try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path])
print("Wrote Resources/AppIcon.icns and Resources/AppIcon.png")
