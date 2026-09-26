//
//  DiffLayout.swift
//  LF-Paper
//

import AppKit

/// Sizes for the side-by-side diff. Each side is as wide as its own longest line and scrolls
/// sideways on its own; every row has the same height, so the two sides always line up.
nonisolated enum DiffLayout {
    /// The longest line on each side, in columns.
    nonisolated struct LongestLines: Equatable, Sendable {
        let left: Int
        let right: Int
    }

    static let fontSize: CGFloat = 12
    /// Computed because `NSFont` isn't `Sendable`; AppKit caches system fonts, so this is cheap.
    static var font: NSFont { .monospacedSystemFont(ofSize: fontSize, weight: .regular) }
    /// Width of one character in the monospaced diff font.
    static let characterWidth: CGFloat = ceil(("M" as NSString).size(withAttributes: [.font: font]).width)
    /// The height of one line of text in the font.
    static let lineHeight: CGFloat = ceil(NSLayoutManager().defaultLineHeight(for: font))
    /// One line of the font plus a little room above and below.
    static let rowHeight: CGFloat = lineHeight + 3
    static let tabWidth = 4
    /// The fixed line-number column on the left of each side.
    static let gutterWidth: CGFloat = 44
    /// Space between the line numbers and the text, and after the longest line.
    static let textInset: CGFloat = 8
    /// Lines longer than this are cut with "…": drawing megabyte-long lines stalls the view.
    static let maximumVisibleCharacters = 5_000

    static func longestLines(in rows: [SideBySideRow]) -> LongestLines {
        rows.reduce(LongestLines(left: 0, right: 0)) { longest, row in
            LongestLines(
                left: max(longest.left, columns(in: row.left?.text ?? "")),
                right: max(longest.right, columns(in: row.right?.text ?? ""))
            )
        }
    }

    /// Characters as they take up space, with a tab as `tabWidth` columns.
    static func columns(in text: String) -> Int {
        text.reduce(0) { $0 + ($1 == "\t" ? tabWidth : 1) }
    }

    /// A side's scrollable width: what's visible, or wider when its longest line needs it.
    static func documentWidth(longestLine: Int, visibleWidth: CGFloat) -> CGFloat {
        let visible = min(longestLine, maximumVisibleCharacters + 1)
        return max(visibleWidth, textInset * 2 + CGFloat(visible) * characterWidth)
    }

    static func visibleText(_ text: String) -> String {
        text.count > maximumVisibleCharacters ? String(text.prefix(maximumVisibleCharacters)) + "…" : text
    }
}
