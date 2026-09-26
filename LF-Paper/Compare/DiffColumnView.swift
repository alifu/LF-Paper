//
//  DiffColumnView.swift
//  LF-Paper
//

import AppKit

/// One side of the side-by-side diff: draws only the rows in view, each `DiffLayout.rowHeight` tall.
/// Removed lines are red, added lines green, and inside a changed pair the parts that differ get a
/// stronger tint. It is the scroll view's document, as wide as its longest line.
final class DiffColumnView: NSView {
    enum Side {
        case left, right
    }

    /// A whole changed line, when there's no word-level detail.
    private static let lineTint: CGFloat = 0.18
    /// The rest of a line whose changed parts are highlighted.
    private static let quietLineTint: CGFloat = 0.09
    /// The changed parts themselves.
    private static let changeTint: CGFloat = 0.4
    /// A row where only the other side has a line.
    private static let absentTint: CGFloat = 0.08

    let side: Side
    private(set) var cells: [DiffCell?] = []

    init(side: Side) {
        self.side = side
        super.init(frame: .zero)
        setAccessibilityRole(.list)
        setAccessibilityLabel(side == .left ? "Old version" : "New version")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    func show(_ rows: [SideBySideRow]) {
        cells = rows.map { side == .left ? $0.left : $0.right }
        needsDisplay = true
    }

    /// The tint behind a row, shared with the line-number gutter.
    static func background(for cell: DiffCell?) -> NSColor? {
        guard let cell else { return NSColor.gray.withAlphaComponent(absentTint) }
        guard let tint = tint(for: cell.kind) else { return nil }
        return tint.withAlphaComponent(cell.changedRanges == nil ? lineTint : quietLineTint)
    }

    static func rowRect(_ row: Int, width: CGFloat) -> NSRect {
        NSRect(x: 0, y: CGFloat(row) * DiffLayout.rowHeight, width: width, height: DiffLayout.rowHeight)
    }

    /// The rows touching `rect` (in this view's coordinates).
    func rows(in rect: NSRect) -> Range<Int> {
        let first = max(0, Int(floor(rect.minY / DiffLayout.rowHeight)))
        let last = min(cells.count, Int(ceil(rect.maxY / DiffLayout.rowHeight)))
        return first < last ? first..<last : 0..<0
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        for row in rows(in: dirtyRect) {
            draw(row: row)
        }
    }

    private func draw(row: Int) {
        let rect = Self.rowRect(row, width: bounds.width)
        let cell = cells[row]
        if let background = Self.background(for: cell) {
            background.setFill()
            rect.fill(using: .sourceOver)
        }
        guard let cell else { return }
        let text = Self.attributedText(for: cell)
        text.draw(at: NSPoint(x: DiffLayout.textInset, y: rect.minY + (rect.height - DiffLayout.lineHeight) / 2))
    }

    private static func attributedText(for cell: DiffCell) -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: DiffLayout.visibleText(cell.text),
            attributes: [.font: DiffLayout.font, .foregroundColor: NSColor.textColor]
        )
        if let tint = tint(for: cell.kind), let ranges = cell.changedRanges {
            for range in ranges where NSMaxRange(range) <= text.length {
                text.addAttribute(.backgroundColor, value: tint.withAlphaComponent(changeTint), range: range)
            }
        }
        return text
    }

    private static func tint(for kind: TextDiffLine.Kind) -> NSColor? {
        switch kind {
        case .removed: .systemRed
        case .added: .systemGreen
        case .same: nil
        }
    }

    // MARK: Accessibility

    /// One element per visible line, read as "Removed line 2: …", since colour alone carries the change.
    override func accessibilityChildren() -> [Any]? {
        rows(in: visibleRect).compactMap { row -> NSAccessibilityElement? in
            guard let cell = cells[row] else { return nil }
            let rect = Self.rowRect(row, width: bounds.width)
            let frame = window == nil ? rect : NSAccessibility.screenRect(fromView: self, rect: rect)
            return NSAccessibilityElement.element(withRole: .staticText, frame: frame, label: cell.accessibilityDescription, parent: self) as? NSAccessibilityElement
        }
    }
}
