//
//  EditorThemeRenderingTests.swift
//  LF-PaperTests
//

import AppKit
import SwiftUI
import Testing
@testable import LF_Paper

/// Renders Markdown and JSON in Hyrule and Hyrule Light offscreen: the background, the current
/// line and the token colours are checked by pixel, and the images are attached to look at.
@MainActor
struct EditorThemeRenderingTests {
    private static let size = NSSize(width: 520, height: 260)

    private nonisolated static let markdown = """
        # Hyrule theme
        Some *italic* and **bold** text, `inline code`, a [link](https://example.com).
        > A quote
        - item 1
        <!-- a comment -->
        """

    private nonisolated static let json = """
        {
          "name": "Ada",
          "count": 42,
          "active": true,
          "tags": ["math", null]
        }
        """

    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let appearance: NSAppearance.Name
        let isDark: Bool
        let fileKind: FileKind
        let text: String

        var testDescription: String { name }
    }

    nonisolated static let cases: [Case] = [
        Case(name: "hyrule-markdown", appearance: .darkAqua, isDark: true, fileKind: .markdown, text: markdown),
        Case(name: "hyrule-light-markdown", appearance: .aqua, isDark: false, fileKind: .markdown, text: markdown),
        Case(name: "hyrule-json", appearance: .darkAqua, isDark: true, fileKind: .json, text: json),
        Case(name: "hyrule-light-json", appearance: .aqua, isDark: false, fileKind: .json, text: json),
    ]

    @Test(arguments: cases)
    func drawsTheThemesColours(_ testCase: Case) throws {
        let palette = EditorPalette.palette(for: .hyrule, isDark: testCase.isDark)
        let editor = CodeTextView(text: testCase.text, documentID: UUID(), fileKind: testCase.fileKind, palette: palette, onTextChange: { _ in })

        let bitmap = try OffscreenRenderer.render(editor, size: Self.size, appearance: testCase.appearance)
        try OffscreenRenderer.attach(bitmap, named: "\(testCase.name).png")

        let scale = CGFloat(bitmap.pixelsWide) / Self.size.width
        func color(atX x: CGFloat, y: CGFloat) -> NSColor? {
            bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))
        }
        // Below the text, at the right: plain background. On the first line (the cursor's), at the right: the highlight.
        let background = try swatch(palette.background, appearance: testCase.appearance)
        let currentLine = try swatch(try #require(palette.currentLine), appearance: testCase.appearance)
        #expect(matches(color(atX: Self.size.width - 30, y: Self.size.height - 10), background), "background")
        #expect(matches(color(atX: Self.size.width - 30, y: 14), currentLine), "current line")
        for kind in [TokenKind.string, .number] where testCase.fileKind == .json {
            let tokenColor = try swatch(try #require(palette.style(for: kind).color), appearance: testCase.appearance)
            #expect(pixels(in: bitmap, near: tokenColor) > 20, "\(kind) should be drawn in its colour")
        }
    }

    /// The gutter shares the editor's background.
    @Test(arguments: [true, false])
    func theGutterMatchesTheEditor(isDark: Bool) throws {
        let palette = EditorPalette.palette(for: .hyrule, isDark: isDark)
        let editor = CodeTextView(text: "one\ntwo", documentID: UUID(), fileKind: nil, palette: palette, onTextChange: { _ in })

        let bitmap = try OffscreenRenderer.render(editor, size: Self.size, appearance: isDark ? .darkAqua : .aqua)

        let scale = CGFloat(bitmap.pixelsWide) / Self.size.width
        let background = try swatch(palette.background, appearance: isDark ? .darkAqua : .aqua)
        #expect(matches(bitmap.colorAt(x: Int(4 * scale), y: Int((Self.size.height - 10) * scale)), background))
    }

    /// The colour as it comes out of the same offscreen drawing, so colour-profile conversions cancel out.
    private func swatch(_ color: NSColor, appearance: NSAppearance.Name) throws -> NSColor {
        let bitmap = try OffscreenRenderer.render(Color(nsColor: color), size: NSSize(width: 8, height: 8), appearance: appearance)
        return try #require(bitmap.colorAt(x: 2, y: 2))
    }

    private func matches(_ color: NSColor?, _ expected: NSColor, tolerance: CGFloat = 0.02) -> Bool {
        guard let color = color?.usingColorSpace(.deviceRGB), let expected = expected.usingColorSpace(.deviceRGB) else { return false }
        return abs(color.redComponent - expected.redComponent) <= tolerance
            && abs(color.greenComponent - expected.greenComponent) <= tolerance
            && abs(color.blueComponent - expected.blueComponent) <= tolerance
    }

    private func pixels(in bitmap: NSBitmapImageRep, near expected: NSColor) -> Int {
        var count = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 1) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 1) where matches(bitmap.colorAt(x: x, y: y), expected, tolerance: 0.04) {
                count += 1
            }
        }
        return count
    }
}
