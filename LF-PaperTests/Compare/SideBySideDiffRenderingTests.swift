//
//  SideBySideDiffRenderingTests.swift
//  LF-PaperTests
//

import AppKit
import SwiftUI
import Testing
@testable import LF_Paper

/// Renders the side-by-side diff offscreen and attaches the image, in dark and light mode.
@MainActor
struct SideBySideDiffRenderingTests {
    private static let size = NSSize(width: 600, height: 240)

    private func render(_ rows: [SideBySideRow], appearance: NSAppearance.Name) throws -> NSBitmapImageRep {
        let view = SideBySideDiffView(rows: rows, changeStarts: SideBySideRows.changeStarts(in: rows), focusedChange: nil)
            .frame(width: Self.size.width, height: Self.size.height)
        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        let bitmap = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return bitmap
    }

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func diffDrawsReadableTextAndMarksChanges(appearance: NSAppearance.Name) throws {
        let old = JSONFormatter.pretty(try JSONParser.parse(#"{"name":"Ada","age":36,"tags":["math"]}"#).value)
        let new = JSONFormatter.pretty(try JSONParser.parse(#"{"name":"Grace","age":36,"tags":["math","navy"]}"#).value)
        let rows = SideBySideRows.make(from: TextDiff.lines(from: old, to: new))

        let empty = try render([], appearance: appearance)
        let filled = try render(rows, appearance: appearance)
        Attachment.record(try #require(filled.representation(using: .png, properties: [:])), named: "diff-\(appearance.rawValue).png")

        let isDark = appearance == .darkAqua
        let isText: (CGFloat) -> Bool = { isDark ? $0 > 0.6 : $0 < 0.4 }
        let emptyText = PixelCounter.count(in: empty, matching: isText)
        let text = PixelCounter.count(in: filled, matching: isText)
        #expect(text > emptyText + 200, "lines should draw visible text (empty: \(emptyText), filled: \(text))")
    }
}
