#!/usr/bin/env swift
//
//  make-app-icon.swift
//  Draws the LF-Paper app icon at every macOS size into the asset catalog.
//
//  Usage: swift scripts/make-app-icon.swift [path/to/AppIcon.appiconset]
//

import AppKit

let outputFolder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
    ?? "LF-Paper/Assets.xcassets/AppIcon.appiconset")

/// (point size, scale) pairs macOS asks for.
let variants: [(size: Int, scale: Int)] = [16, 32, 128, 256, 512].flatMap { [($0, 1), ($0, 2)] }

func drawIcon(pixels: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(pixels), pixelsHigh: Int(pixels),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let unit = pixels / 1024 // design on a 1024 grid

    // Background: Apple's icon grid leaves a margin around an 824 pt rounded square.
    let tile = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * unit, yRadius: 185 * unit)
    NSGradient(starting: NSColor(red: 0.36, green: 0.30, blue: 0.93, alpha: 1),
               ending: NSColor(red: 0.62, green: 0.28, blue: 0.86, alpha: 1))!
        .draw(in: tilePath, angle: -60)

    // A sheet of paper with a folded corner.
    let fold: CGFloat = 130 * unit
    let sheet = NSRect(x: 270 * unit, y: 190 * unit, width: 484 * unit, height: 620 * unit)
    let paper = NSBezierPath()
    paper.move(to: NSPoint(x: sheet.minX, y: sheet.minY))
    paper.line(to: NSPoint(x: sheet.maxX, y: sheet.minY))
    paper.line(to: NSPoint(x: sheet.maxX, y: sheet.maxY - fold))
    paper.line(to: NSPoint(x: sheet.maxX - fold, y: sheet.maxY))
    paper.line(to: NSPoint(x: sheet.minX, y: sheet.maxY))
    paper.close()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowOffset = NSSize(width: 0, height: -12 * unit)
    shadow.shadowBlurRadius = 30 * unit
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.white.setFill()
    paper.fill()
    NSGraphicsContext.restoreGraphicsState()

    let corner = NSBezierPath()
    corner.move(to: NSPoint(x: sheet.maxX - fold, y: sheet.maxY))
    corner.line(to: NSPoint(x: sheet.maxX - fold, y: sheet.maxY - fold))
    corner.line(to: NSPoint(x: sheet.maxX, y: sheet.maxY - fold))
    corner.close()
    NSColor(white: 0.85, alpha: 1).setFill()
    corner.fill()

    // "{ }" for JSON, and text lines for Markdown.
    let braces = NSAttributedString(string: "{ }", attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 190 * unit, weight: .bold),
        .foregroundColor: NSColor(red: 0.42, green: 0.29, blue: 0.90, alpha: 1),
    ])
    let bracesSize = braces.size()
    braces.draw(at: NSPoint(x: sheet.midX - bracesSize.width / 2, y: 470 * unit))

    NSColor(white: 0.78, alpha: 1).setFill()
    for (index, width) in [330.0, 280, 310].enumerated() {
        let line = NSRect(x: 347 * unit, y: CGFloat(390 - index * 70) * unit, width: CGFloat(width) * unit, height: 30 * unit)
        NSBezierPath(roundedRect: line, xRadius: 15 * unit, yRadius: 15 * unit).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

var images: [[String: String]] = []
for variant in variants {
    let pixels = variant.size * variant.scale
    let name = "icon_\(variant.size)x\(variant.size)@\(variant.scale)x.png"
    let png = drawIcon(pixels: CGFloat(pixels)).representation(using: .png, properties: [:])!
    try png.write(to: outputFolder.appending(path: name))
    images.append(["idiom": "mac", "scale": "\(variant.scale)x", "size": "\(variant.size)x\(variant.size)", "filename": name])
}

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outputFolder.appending(path: "Contents.json"))
print("Wrote \(variants.count) icons to \(outputFolder.path)")
