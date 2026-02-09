#!/usr/bin/env swift

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Generates a minimalist app icon for ErgScan
/// Design: Clipboard with rowing machine line art on a gradient background

func generateAppIcon(size: Int) -> CGImage? {
    let dimension = CGFloat(size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    guard let context = CGContext(
        data: nil,
        width: Int(dimension),
        height: Int(dimension),
        bitsPerComponent: 8,
        bytesPerRow: Int(dimension) * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }

    let rect = CGRect(x: 0, y: 0, width: dimension, height: dimension)

    // Background: Blue gradient (lighter to darker)
    let gradientColors = [
        CGColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0),  // Light blue
        CGColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1.0)   // Darker blue
    ] as CFArray

    if let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: gradientColors,
        locations: [0.0, 1.0]
    ) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 0, y: dimension),
            options: []
        )
    }

    // Draw minimalist clipboard with rowing machine icon
    context.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    context.setStrokeColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)

    let scale = dimension / 1024.0
    let lineWidth = 40.0 * scale
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    // Clipboard outline (simplified)
    let clipboardRect = CGRect(
        x: dimension * 0.25,
        y: dimension * 0.15,
        width: dimension * 0.5,
        height: dimension * 0.7
    )

    // Rounded rectangle for clipboard
    let clipPath = CGPath(
        roundedRect: clipboardRect,
        cornerWidth: 40 * scale,
        cornerHeight: 40 * scale,
        transform: nil
    )
    context.addPath(clipPath)
    context.setLineWidth(30 * scale)
    context.strokePath()

    // Clipboard clip at top (small rectangle)
    let clipRect = CGRect(
        x: dimension * 0.42,
        y: dimension * 0.10,
        width: dimension * 0.16,
        height: dimension * 0.08
    )
    let clipClipPath = CGPath(
        roundedRect: clipRect,
        cornerWidth: 15 * scale,
        cornerHeight: 15 * scale,
        transform: nil
    )
    context.addPath(clipClipPath)
    context.fillPath()

    // Rowing machine silhouette (simplified geometric version)
    // Draw three horizontal lines representing workout data rows
    context.setLineWidth(25 * scale)

    let lineY1 = dimension * 0.35
    let lineY2 = dimension * 0.50
    let lineY3 = dimension * 0.65
    let lineStartX = dimension * 0.33
    let lineEndX = dimension * 0.67

    // Line 1
    context.move(to: CGPoint(x: lineStartX, y: lineY1))
    context.addLine(to: CGPoint(x: lineEndX, y: lineY1))

    // Line 2
    context.move(to: CGPoint(x: lineStartX, y: lineY2))
    context.addLine(to: CGPoint(x: lineEndX, y: lineY2))

    // Line 3
    context.move(to: CGPoint(x: lineStartX, y: lineY3))
    context.addLine(to: CGPoint(x: lineEndX, y: lineY3))

    context.strokePath()

    return context.makeImage()
}

func saveImage(_ image: CGImage, to path: String) -> Bool {
    let url = URL(fileURLWithPath: path)

    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        print("❌ Failed to create destination for \(path)")
        return false
    }

    CGImageDestinationAddImage(destination, image, nil)

    if CGImageDestinationFinalize(destination) {
        print("✅ Generated: \(url.lastPathComponent)")
        return true
    } else {
        print("❌ Failed to save: \(path)")
        return false
    }
}

// Generate icons
let outputDir = "/Users/omomalley03/Desktop/ErgScan1/ErgScan1/Assets.xcassets/AppIcon.appiconset"

print("🎨 Generating ErgScan app icons...")
print("")

// Generate 1024x1024 icon (standard)
if let icon = generateAppIcon(size: 1024) {
    _ = saveImage(icon, to: "\(outputDir)/icon-1024.png")
}

print("")
print("✅ App icon generation complete!")
print("💡 Xcode will automatically resize the 1024x1024 icon for all required sizes")
