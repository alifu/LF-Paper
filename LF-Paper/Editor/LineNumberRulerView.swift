//
//  LineNumberRulerView.swift
//  LF-Paper
//

import AppKit

/// Line numbers in the gutter of a TextKit 1 `NSTextView`. Numbers count "\n" lines,
/// so a long wrapped line gets one number.
final class LineNumberRulerView: NSRulerView {
    private static let horizontalPadding: CGFloat = 8
    private static let minimumDigits = 3

    private let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.secondaryLabelColor,
    ]
    private weak var textView: NSTextView?
    private var lineIndex = LineIndex(text: "")

    /// Call after the text view is the scroll view's document view.
    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        // Since macOS 14 views don't clip drawing to their bounds by default; without this
        // the ruler's background paints over the text next to it and the editor looks empty.
        clipsToBounds = true
        clientView = textView
        updateThickness()
        observeLayoutChanges(of: textView)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    /// Re-counts lines. The editor calls this whenever the characters change.
    func textDidChange() {
        guard let text = textView?.textStorage?.mutableString else { return }
        lineIndex = LineIndex(text: text)
        updateThickness()
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return }

        NSColor.textBackgroundColor.setFill()
        bounds.intersection(rect).fill()

        let visibleGlyphs = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: textContainer)
        let visibleCharacters = layoutManager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        let textLength = textView.textStorage?.length ?? 0

        var line = lineIndex.lineNumber(at: visibleCharacters.location)
        while line <= lineIndex.lineCount {
            let lineStart = lineIndex.lineStarts[line - 1]
            guard lineStart <= NSMaxRange(visibleCharacters) else { break }
            let fragment = lineStart < textLength
                ? layoutManager.lineFragmentRect(
                    forGlyphAt: layoutManager.glyphIndexForCharacter(at: lineStart),
                    effectiveRange: nil
                )
                : layoutManager.extraLineFragmentRect // the empty line after a trailing newline
            drawLabel(for: line, alignedWith: fragment, in: textView)
            line += 1
        }
    }

    private func drawLabel(for line: Int, alignedWith fragment: NSRect, in textView: NSTextView) {
        let label = String(line) as NSString
        let size = label.size(withAttributes: labelAttributes)
        let fragmentTop = convert(NSPoint(x: 0, y: fragment.minY + textView.textContainerOrigin.y), from: textView).y
        let origin = NSPoint(
            x: ruleThickness - Self.horizontalPadding - size.width,
            y: fragmentTop + (fragment.height - size.height) / 2
        )
        label.draw(at: origin, withAttributes: labelAttributes)
    }

    private func updateThickness() {
        let digits = max(Self.minimumDigits, String(lineIndex.lineCount).count)
        let digitWidth = ("8" as NSString).size(withAttributes: labelAttributes).width
        let thickness = ceil(CGFloat(digits) * digitWidth + 2 * Self.horizontalPadding)
        if ruleThickness != thickness {
            ruleThickness = thickness
        }
    }

    /// Redraw when scrolling or when resizing re-wraps lines.
    private func observeLayoutChanges(of textView: NSTextView) {
        let center = NotificationCenter.default
        if let clipView = textView.enclosingScrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
            center.addObserver(self, selector: #selector(layoutDidChange), name: NSView.boundsDidChangeNotification, object: clipView)
        }
        textView.postsFrameChangedNotifications = true
        center.addObserver(self, selector: #selector(layoutDidChange), name: NSView.frameDidChangeNotification, object: textView)
    }

    @objc private func layoutDidChange(_ notification: Notification) {
        needsDisplay = true
    }
}
