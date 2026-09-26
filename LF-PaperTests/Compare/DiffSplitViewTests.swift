//
//  DiffSplitViewTests.swift
//  LF-PaperTests
//

import AppKit
import SwiftUI
import Testing
@testable import LF_Paper

/// The side-by-side diff: each side scrolls sideways on its own, vertical scrolling moves both
/// together, and only the visible rows are drawn.
@MainActor
struct DiffSplitViewTests {
    private static let size = NSSize(width: 600, height: 200)
    private static let longLine = "The start of a very long line " + String(repeating: "that keeps going ", count: 30) + "END"

    private func makeSplit(_ rows: [SideBySideRow], focusedRows: Range<Int>? = nil) -> DiffSplitView {
        let split = DiffSplitView(frame: NSRect(origin: .zero, size: Self.size))
        split.show(rows: rows, longestLines: DiffLayout.longestLines(in: rows), focusedRows: focusedRows)
        split.layoutSubtreeIfNeeded()
        return split
    }

    private func rows(old: String, new: String) -> [SideBySideRow] {
        SideBySideRows.make(from: TextDiff.lines(from: old, to: new))
    }

    private func manyRows(_ count: Int) -> [SideBySideRow] {
        let text = (1...count).map { "line \($0)" }.joined(separator: "\n")
        return rows(old: text, new: text.replacingOccurrences(of: "line 80\n", with: "line eighty\n"))
    }

    private func scroll(_ scrollView: NSScrollView, to point: NSPoint) {
        scrollView.contentView.scroll(to: point)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func origin(_ scrollView: NSScrollView) -> NSPoint {
        scrollView.contentView.bounds.origin
    }

    // MARK: Scrolling

    @Test func eachSideIsAsWideAsItsOwnLongestLine() {
        let split = makeSplit(rows(old: "# Title\n" + Self.longLine + "\n", new: "# Title\nshort\n"))

        #expect(split.leftColumn.frame.width > DiffSplitView.textWidth(of: split.leftScrollView))
        #expect(split.rightColumn.frame.width == DiffSplitView.textWidth(of: split.rightScrollView))
        #expect(split.leftScrollView.hasHorizontalScroller)
        #expect(split.rightScrollView.hasHorizontalScroller)
    }

    @Test func scrollingOneSideSidewaysLeavesTheOtherAlone() {
        let long = Self.longLine
        let split = makeSplit(rows(old: long + "\n", new: long.replacingOccurrences(of: "start", with: "beginning") + "\n"))

        let rightStart = origin(split.rightScrollView).x

        scroll(split.leftScrollView, to: NSPoint(x: 200, y: 0))

        #expect(origin(split.leftScrollView).x == 200)
        #expect(origin(split.rightScrollView).x == rightStart)
    }

    @Test func scrollingUpOrDownMovesBothSides() {
        let long = Self.longLine + "\n"
        let split = makeSplit(rows(old: long + (1...100).map { "\($0)" }.joined(separator: "\n"), new: long + (1...100).map { "\($0)" }.joined(separator: "\n")))
        scroll(split.leftScrollView, to: NSPoint(x: 50, y: 0))

        scroll(split.rightScrollView, to: NSPoint(x: 0, y: 300))
        #expect(origin(split.leftScrollView).y == 300)
        #expect(origin(split.leftScrollView).x == 50) // its own sideways position is kept

        scroll(split.leftScrollView, to: NSPoint(x: 50, y: 120))
        #expect(origin(split.rightScrollView).y == 120)
    }

    @Test func rowsLineUpOnBothSides() {
        let rows = manyRows(100)
        let split = makeSplit(rows)

        #expect(split.leftColumn.frame.height == CGFloat(rows.count) * DiffLayout.rowHeight)
        #expect(split.rightColumn.frame.height == split.leftColumn.frame.height)
    }

    @Test func showingAChangeScrollsBothSidesToItAndToTheStartOfTheLines() {
        let split = makeSplit(manyRows(200))
        scroll(split.leftScrollView, to: NSPoint(x: 30, y: 0))

        split.scrollToRow(79)

        let rowTop = 79 * DiffLayout.rowHeight
        for scrollView in [split.leftScrollView, split.rightScrollView] {
            let visible = scrollView.contentView.bounds
            #expect(visible.minY <= rowTop && rowTop + DiffLayout.rowHeight <= visible.maxY)
            #expect(visible.minX == DiffSplitView.lineStartX(of: scrollView))
        }
    }

    @Test func newRowsResizeBothSides() {
        let split = makeSplit(manyRows(10))

        split.show(rows: manyRows(50), longestLines: DiffLayout.longestLines(in: manyRows(50)), focusedRows: nil)
        split.layoutSubtreeIfNeeded()

        #expect(split.leftColumn.frame.height == 50 * DiffLayout.rowHeight)
    }

    /// Next Change in the Compare window: the SwiftUI view scrolls the split to the focused change.
    @Test func focusingAChangeFromSwiftUIScrollsToIt() throws {
        let rows = manyRows(200)
        let changeStarts = SideBySideRows.changeStarts(in: rows)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: SideBySideDiffView(rows: rows, changeStarts: changeStarts, focusedChange: nil))
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        host.rootView = SideBySideDiffView(rows: rows, changeStarts: changeStarts, focusedChange: 0)
        host.layoutSubtreeIfNeeded()

        let split = try #require(Self.firstSubview(of: DiffSplitView.self, in: host))
        let visible = split.rightScrollView.contentView.bounds
        let rowTop = CGFloat(changeStarts[0]) * DiffLayout.rowHeight
        #expect(visible.minY <= rowTop && rowTop < visible.maxY, "row \(changeStarts[0]) should be in view (visible \(visible))")
    }

    private static func firstSubview<View: NSView>(of type: View.Type, in view: NSView) -> View? {
        if let match = view as? View { return match }
        return view.subviews.lazy.compactMap { firstSubview(of: type, in: $0) }.first
    }

    // MARK: Drawing

    /// Pixels in the strong word highlight: one channel clearly outweighs the other. The light
    /// line tint stays well below these margins; system green is less saturated than red.
    private func tintedPixels(in bitmap: NSBitmapImageRep, xRange: Range<Int>, red: Bool) -> Int {
        let margin = red ? 0.25 : 0.15
        var count = 0
        for x in xRange {
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let difference = red ? color.redComponent - color.greenComponent : color.greenComponent - color.redComponent
                if difference > margin { count += 1 }
            }
        }
        return count
    }

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func drawsRemovedWordsOnTheLeftAndAddedWordsOnTheRight(appearance: NSAppearance.Name) throws {
        let split = makeSplit(rows(old: "{\n  \"name\": \"Ada\",\n  \"age\": 36\n}\n", new: "{\n  \"name\": \"Grace\",\n  \"age\": 36\n}\n"))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = split
        split.layoutSubtreeIfNeeded()

        let bitmap = try #require(split.bitmapImageRepForCachingDisplay(in: split.bounds))
        split.cacheDisplay(in: split.bounds, to: bitmap)
        try OffscreenRenderer.attach(bitmap, named: "diff-split-\(appearance.rawValue).png")

        let half = bitmap.pixelsWide / 2
        #expect(tintedPixels(in: bitmap, xRange: 0..<half, red: true) > 40, "“Ada” should be marked on the left")
        #expect(tintedPixels(in: bitmap, xRange: half..<bitmap.pixelsWide, red: false) > 40, "“Grace” should be marked on the right")
        #expect(tintedPixels(in: bitmap, xRange: half..<bitmap.pixelsWide, red: true) == 0, "nothing removed on the right")
        #expect(OffscreenRenderer.contentPixels(in: bitmap, appearance: appearance) > 120, "the lines should be readable")
    }

    // MARK: Accessibility

    @Test func visibleRowsAreReadAsLinesWithTheirChange() throws {
        let split = makeSplit(rows(old: "same\nold\n", new: "same\nnew\n"))

        let left = try #require(split.leftColumn.accessibilityChildren() as? [NSAccessibilityElement])
        let right = try #require(split.rightColumn.accessibilityChildren() as? [NSAccessibilityElement])

        #expect(left.map { $0.accessibilityLabel() } == ["Line 1: same", "Removed line 2: old"])
        #expect(right.map { $0.accessibilityLabel() } == ["Line 1: same", "Added line 2: new"])
        #expect(split.leftColumn.accessibilityLabel() == "Old version")
    }
}
