//
//  CodeEditorTextView.swift
//  LF-Paper
//

import AppKit

/// The editor's text view: an `NSTextView` that can highlight the line with the cursor.
final class CodeEditorTextView: NSTextView {
    /// Drawn behind the line with the cursor while nothing is selected; `nil` draws nothing.
    var currentLineColor: NSColor? {
        didSet {
            if currentLineColor != oldValue { needsDisplay = true }
        }
    }

    /// Where the highlight was last drawn, so moving the cursor only redraws two lines.
    private var highlightedLineRect: NSRect?

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let currentLineColor, let lineRect = currentLineRect() else { return }
        currentLineColor.setFill()
        lineRect.intersection(rect).fill(using: .sourceOver)
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        guard currentLineColor != nil else { return }
        let newRect = currentLineRect()
        guard newRect != highlightedLineRect else { return }
        [highlightedLineRect, newRect].compactMap { $0 }.forEach { setNeedsDisplay($0) }
        highlightedLineRect = newRect
    }

    /// The full-width rectangle of the line fragment with the cursor, or `nil` with a selection.
    private func currentLineRect() -> NSRect? {
        guard let layoutManager, selectedRange().length == 0 else { return nil }
        let location = selectedRange().location
        let fragment: NSRect
        if location < (textStorage?.length ?? 0) {
            let glyph = layoutManager.glyphIndexForCharacter(at: location)
            fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        } else if !layoutManager.extraLineFragmentRect.isEmpty {
            fragment = layoutManager.extraLineFragmentRect // the empty last line
        } else if let last = textStorage?.length, last > 0 {
            fragment = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: last - 1), effectiveRange: nil)
        } else {
            return nil
        }
        return NSRect(x: bounds.minX, y: fragment.minY + textContainerOrigin.y, width: bounds.width, height: fragment.height)
    }
}
