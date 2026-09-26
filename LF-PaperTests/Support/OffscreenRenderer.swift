//
//  OffscreenRenderer.swift
//  LF-PaperTests
//

import AppKit
import SwiftUI
import Testing

/// Draws a SwiftUI view into a bitmap in a window-less, offscreen window, so render tests can
/// check pixels and attach the image for review.
@MainActor
enum OffscreenRenderer {
    static func render(_ view: some View, size: NSSize, appearance: NSAppearance.Name) throws -> NSBitmapImageRep {
        let hostingView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        let bitmap = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return bitmap
    }

    static func attach(_ bitmap: NSBitmapImageRep, named name: String) throws {
        Attachment.record(try #require(bitmap.representation(using: .png, properties: [:])), named: name)
    }

    /// Pixels that stand out as text or icons against the window background.
    /// Loose enough for small, secondary-gray, antialiased text.
    static func contentPixels(in bitmap: NSBitmapImageRep, appearance: NSAppearance.Name) -> Int {
        let isDark = appearance == .darkAqua
        return PixelCounter.count(in: bitmap) { isDark ? $0 > 0.5 : $0 < 0.6 }
    }

    /// The same count for an empty window of `size`, the baseline to compare against.
    static func blankContentPixels(size: NSSize, appearance: NSAppearance.Name) throws -> Int {
        let blank = try render(Color(nsColor: .windowBackgroundColor), size: size, appearance: appearance)
        return contentPixels(in: blank, appearance: appearance)
    }
}
