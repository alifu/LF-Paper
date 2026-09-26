//
//  WordHighlightRenderingTests.swift
//  LF-PaperTests
//

import AppKit
import Testing
@testable import LF_Paper

/// The changed word inside a changed line gets a strong tint; the rest of the line a light one.
@MainActor
struct WordHighlightRenderingTests {
    private static let width: CGFloat = 320

    /// Pixels whose red clearly outweighs green: the strong "removed" highlight, not the light line tint.
    private func stronglyRedPixels(in bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent - color.greenComponent > 0.25 { count += 1 }
            }
        }
        return count
    }

    private func render(_ cell: DiffCell, appearance: NSAppearance.Name, name: String) throws -> NSBitmapImageRep {
        let column = DiffColumnView(side: .left)
        column.appearance = NSAppearance(named: appearance)
        column.frame = NSRect(x: 0, y: 0, width: Self.width, height: DiffLayout.rowHeight)
        column.show([SideBySideRow(id: 0, left: cell, right: nil)])
        let bitmap = try #require(column.bitmapImageRepForCachingDisplay(in: column.bounds))
        column.cacheDisplay(in: column.bounds, to: bitmap)
        try OffscreenRenderer.attach(bitmap, named: "\(name)-\(appearance.rawValue).png")
        return bitmap
    }

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func onlyTheChangedWordIsStronglyTinted(appearance: NSAppearance.Name) throws {
        let text = #"  "name": "Ada","#
        let word = try render(
            DiffCell(lineNumber: 2, text: text, kind: .removed, changedRanges: [NSRange(location: 11, length: 3)]),
            appearance: appearance,
            name: "word-highlight"
        )
        let wholeLine = try render(DiffCell(lineNumber: 2, text: text, kind: .removed), appearance: appearance, name: "line-highlight")

        let wordPixels = stronglyRedPixels(in: word)
        #expect(wordPixels > 40, "the changed word should stand out (strong pixels: \(wordPixels))")
        #expect(wordPixels < word.pixelsWide * word.pixelsHigh / 5, "only the word, not the whole line (strong pixels: \(wordPixels))")
        #expect(stronglyRedPixels(in: wholeLine) == 0, "a whole changed line keeps the lighter tint")
    }
}
