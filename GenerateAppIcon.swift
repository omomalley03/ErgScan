#!/usr/bin/env swift

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Generates a minimalist app icon for ErgScan
/// Design: Red background with white hardhat icon

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

    // Background: Red gradient (lighter to darker)
    let gradientColors = [
        CGColor(red: 0.95, green: 0.3, blue: 0.3, alpha: 1.0),  // Light red
        CGColor(red: 0.8, green: 0.15, blue: 0.15, alpha: 1.0)  // Darker red
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

    // Draw white hardhat icon
    context.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    context.setStrokeColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)

    let scale = dimension / 1024.0
    context.setLineWidth(30 * scale)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    // Hardhat shape
    let centerX = dimension * 0.5
    let centerY = dimension * 0.5

    // Brim of hardhat (bottom rectangle/ellipse)
    let brimRect = CGRect(
        x: dimension * 0.2,
        y: dimension * 0.62,
        width: dimension * 0.6,
        height: dimension * 0.08
    )
    context.addEllipse(in: brimRect)
    context.fillPath()

    // Main dome of hardhat (top semi-circle/rounded rectangle)
    let domeRect = CGRect(
        x: dimension * 0.25,
        y: dimension * 0.28,
        width: dimension * 0.5,
        height: dimension * 0.36
    )

    // Create rounded top for dome
    let domePath = CGMutablePath()
    domePath.move(to: CGPoint(x: domeRect.minX, y: domeRect.maxY))
    domePath.addLine(to: CGPoint(x: domeRect.minX, y: domeRect.midY))
    domePath.addQuadCurve(
        to: CGPoint(x: domeRect.maxX, y: domeRect.midY),
        control: CGPoint(x: centerX, y: domeRect.minY - dimension * 0.05)
    )
    domePath.addLine(to: CGPoint(x: domeRect.maxX, y: domeRect.maxY))
    domePath.closeSubpath()

    context.addPath(domePath)
    context.fillPath()

    // Ridge/vent on top of hardhat
    let ridgeRect = CGRect(
        x: dimension * 0.45,
        y: dimension * 0.26,
        width: dimension * 0.1,
        height: dimension * 0.06
    )
    let ridgePath = CGPath(
        roundedRect: ridgeRect,
        cornerWidth: 10 * scale,
        cornerHeight: 10 * scale,
        transform: nil
    )
    context.addPath(ridgePath)
    context.fillPath()

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
