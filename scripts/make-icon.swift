#!/usr/bin/env swift
import AppKit
import Foundation

// Render every icon size directly so small Dock/Finder icons remain crisp.
let outputDirectory = CommandLine.arguments.dropFirst().first ?? ".build/assets/Screenroom.iconset"
let destination = URL(fileURLWithPath: outputDirectory, isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}

func renderIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "ScreenroomIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create the icon canvas."])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }
    context.imageInterpolation = .high
    context.shouldAntialias = true
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 202, yRadius: 202)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    color(239, 83, 67).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(255, 127, 99), ending: color(231, 67, 64))!.draw(in: tile, angle: -90)

    // A quiet inset stroke adds definition without an ornamental border.
    let innerEdge = NSBezierPath(roundedRect: NSRect(x: 67, y: 67, width: 890, height: 890), xRadius: 199, yRadius: 199)
    NSColor.white.withAlphaComponent(0.16).setStroke()
    innerEdge.lineWidth = 3
    innerEdge.stroke()

    let screen = NSBezierPath(roundedRect: NSRect(x: 247, y: 365, width: 530, height: 352), xRadius: 48, yRadius: 48)
    color(255, 248, 242).setStroke()
    screen.lineWidth = 42
    screen.stroke()
    let stand = NSBezierPath()
    stand.lineCapStyle = .round
    stand.lineJoinStyle = .round
    stand.lineWidth = 36
    stand.move(to: NSPoint(x: 512, y: 353))
    stand.line(to: NSPoint(x: 512, y: 283))
    stand.move(to: NSPoint(x: 421, y: 279))
    stand.line(to: NSPoint(x: 603, y: 279))
    stand.stroke()

    // One capture corner inside the monitor makes the mark legible as a screen tool.
    let corner = NSBezierPath()
    corner.lineCapStyle = .round
    corner.lineJoinStyle = .round
    corner.lineWidth = 24
    corner.move(to: NSPoint(x: 329, y: 562))
    corner.line(to: NSPoint(x: 329, y: 632))
    corner.line(to: NSPoint(x: 399, y: 632))
    NSColor.white.withAlphaComponent(0.72).setStroke()
    corner.stroke()

    let dotBackdrop = NSBezierPath(ovalIn: NSRect(x: 648, y: 254, width: 168, height: 168))
    color(243, 85, 69).setFill()
    dotBackdrop.fill()
    let dot = NSBezierPath(ovalIn: NSRect(x: 673, y: 279, width: 118, height: 118))
    color(255, 248, 242).setFill()
    dot.fill()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ScreenroomIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode the icon as PNG."])
    }
    return png
}

let iconTypes = [
    "16x1": "icp4", "16x2": "ic11",
    "32x1": "icp5", "32x2": "ic12",
    "128x1": "ic07", "128x2": "ic13",
    "256x1": "ic08", "256x2": "ic14",
    "512x1": "ic09", "512x2": "ic10"
]
func bigEndianBytes(_ number: UInt32) -> Data {
    var value = number.bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}

var chunks = Data()
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let filename = "icon_\(points)x\(points)\(suffix).png"
        let png = try renderIcon(pixels: points * scale)
        try png.write(to: destination.appendingPathComponent(filename))
        // Modern ICNS stores PNG representations in typed, big-endian chunks.
        chunks.append(Data(iconTypes["\(points)x\(scale)"]!.utf8))
        chunks.append(bigEndianBytes(UInt32(png.count + 8)))
        chunks.append(png)
    }
}
let iconPath = CommandLine.arguments.dropFirst(2).first
    ?? destination.deletingLastPathComponent().appendingPathComponent("Screenroom.icns").path
var iconData = Data("icns".utf8)
iconData.append(bigEndianBytes(UInt32(chunks.count + 8)))
iconData.append(chunks)
try iconData.write(to: URL(fileURLWithPath: iconPath))
guard let image = NSImage(contentsOfFile: iconPath), !image.representations.isEmpty else {
    throw NSError(domain: "ScreenroomIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "The generated icon failed validation."])
}
print("Generated icon: \(iconPath)")
