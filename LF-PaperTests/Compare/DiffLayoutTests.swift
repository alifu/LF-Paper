//
//  DiffLayoutTests.swift
//  LF-PaperTests
//

import AppKit
import Testing
@testable import LF_Paper

/// Sizes for the side-by-side diff, where each side is as wide as its own longest line.
struct DiffLayoutTests {
    private func rows(old: String, new: String) -> [SideBySideRow] {
        SideBySideRows.make(from: TextDiff.lines(from: old, to: new))
    }

    @Test func measuresTheLongestLineOfEachSide() {
        let rows = rows(old: "short\n" + String(repeating: "a", count: 90), new: "short\n" + String(repeating: "b", count: 120))

        #expect(DiffLayout.longestLines(in: rows) == DiffLayout.LongestLines(left: 90, right: 120))
    }

    @Test func tabsCountAsSeveralColumns() {
        #expect(DiffLayout.columns(in: "\tx") == DiffLayout.tabWidth + 1)
    }

    @Test func shortLinesFillTheVisibleWidth() {
        #expect(DiffLayout.documentWidth(longestLine: 10, visibleWidth: 500) == 500)
    }

    @Test func longLinesMakeTheSideWiderThanWhatIsVisible() {
        let width = DiffLayout.documentWidth(longestLine: 400, visibleWidth: 500)

        #expect(width >= 400 * DiffLayout.characterWidth)
    }

    @Test func hugeLinesAreCutAtTheVisibleLimit() {
        let text = String(repeating: "x", count: DiffLayout.maximumVisibleCharacters + 500)

        #expect(DiffLayout.visibleText(text).count == DiffLayout.maximumVisibleCharacters + 1) // plus "…"
        #expect(DiffLayout.visibleText(text).hasSuffix("…"))
        #expect(DiffLayout.visibleText("short") == "short")
        #expect(
            DiffLayout.documentWidth(longestLine: 1_000_000, visibleWidth: 500)
                == DiffLayout.documentWidth(longestLine: DiffLayout.maximumVisibleCharacters + 1, visibleWidth: 500)
        )
    }

    @Test func rowsAreTallEnoughForTheFont() {
        let font = NSFont.monospacedSystemFont(ofSize: DiffLayout.fontSize, weight: .regular)

        #expect(DiffLayout.rowHeight >= NSLayoutManager().defaultLineHeight(for: font))
    }

    @Test func comparisonsKnowTheLongestLineOfEachSide() {
        let long = String(repeating: "word ", count: 60)
        guard case .compared(let result) = TextComparison.run(left: "a\n", right: "a\n" + long + "\n") else {
            Issue.record("expected a comparison")
            return
        }

        #expect(result.longestLines == DiffLayout.LongestLines(left: 1, right: long.count))
    }
}
