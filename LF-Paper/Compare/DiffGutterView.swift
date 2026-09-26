//
//  DiffGutterView.swift
//  LF-Paper
//

import AppKit

/// Line numbers beside one side of the diff. As a vertical ruler it scrolls up and down with the
/// lines but stays put when the side scrolls sideways. The focused change gets an accent bar here.
final class DiffGutterView: NSRulerView {
    private static let focusBarWidth: CGFloat = 3
    private static let numberPadding: CGFloat = 6

    private weak var column: DiffColumnView?
    var focusedRows: Range<Int>? {
        didSet { needsDisplay = true }
    }

    init(scrollView: NSScrollView, column: DiffColumnView) {
        self.column = column
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        // Views don't clip their drawing by default (since macOS 14); without this the gutter's
        // background paints over the lines beside it and the side looks empty (as in the editor).
        clipsToBounds = true
        clientView = column
        ruleThickness = DiffLayout.gutterWidth
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
    override var requiredThickness: CGFloat { DiffLayout.gutterWidth }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        rect.fill()
        guard let column else { return }

        let visible = column.convert(rect, from: self)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: DiffLayout.fontSize - 1, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        for row in column.rows(in: visible) {
            let rowRect = convert(DiffColumnView.rowRect(row, width: 0), from: column)
            let gutterRow = NSRect(x: 0, y: rowRect.minY, width: bounds.width, height: DiffLayout.rowHeight)
            let cell = column.cells[row]
            if let background = DiffColumnView.background(for: cell) {
                background.setFill()
                gutterRow.fill(using: .sourceOver)
            }
            if focusedRows?.contains(row) == true {
                NSColor.controlAccentColor.setFill()
                NSRect(x: 0, y: gutterRow.minY, width: Self.focusBarWidth, height: gutterRow.height).fill()
            }
            guard let cell else { continue }
            let number = String(cell.lineNumber) as NSString
            let size = number.size(withAttributes: attributes)
            number.draw(
                at: NSPoint(x: gutterRow.maxX - size.width - Self.numberPadding, y: gutterRow.midY - size.height / 2),
                withAttributes: attributes
            )
        }
    }
}
