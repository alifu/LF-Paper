//
//  DiffSplitView.swift
//  LF-Paper
//

import AppKit

/// The old document on the left and the new one on the right, each in its own scroll view:
/// a side scrolls sideways on its own, while scrolling up or down moves both, so the rows stay side by side.
final class DiffSplitView: NSView {
    let leftScrollView = NSScrollView()
    let rightScrollView = NSScrollView()
    let leftColumn = DiffColumnView(side: .left)
    let rightColumn = DiffColumnView(side: .right)
    private let separator = NSBox()
    private var leftGutter: DiffGutterView?
    private var rightGutter: DiffGutterView?
    private var rowCount = 0
    private var longestLines = DiffLayout.LongestLines(left: 0, right: 0)
    /// Set while one side follows the other, so it doesn't echo the scroll back.
    private var isFollowing = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        leftGutter = configure(leftScrollView, showing: leftColumn)
        rightGutter = configure(rightScrollView, showing: rightColumn)
        separator.boxType = .separator
        addSubview(leftScrollView)
        addSubview(separator)
        addSubview(rightScrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func configure(_ scrollView: NSScrollView, showing column: DiffColumnView) -> DiffGutterView {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = column
        let gutter = DiffGutterView(scrollView: scrollView, column: column)
        scrollView.verticalRulerView = gutter
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        return gutter
    }

    // MARK: Content

    func show(rows: [SideBySideRow], longestLines: DiffLayout.LongestLines, focusedRows: Range<Int>?) {
        rowCount = rows.count
        self.longestLines = longestLines
        leftColumn.show(rows)
        rightColumn.show(rows)
        setFocusedRows(focusedRows)
        resizeColumns()
    }

    func setFocusedRows(_ rows: Range<Int>?) {
        leftGutter?.focusedRows = rows
        rightGutter?.focusedRows = rows
    }

    /// Centres the row vertically on both sides and scrolls both back to the start of their lines.
    func scrollToRow(_ row: Int) {
        let visibleHeight = leftScrollView.contentView.bounds.height
        let contentHeight = CGFloat(rowCount) * DiffLayout.rowHeight
        let centred = CGFloat(row) * DiffLayout.rowHeight - (visibleHeight - DiffLayout.rowHeight) / 2
        let y = min(max(centred, 0), max(contentHeight - visibleHeight, 0))
        for scrollView in [leftScrollView, rightScrollView] {
            scrollView.contentView.scroll(to: NSPoint(x: Self.lineStartX(of: scrollView), y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    /// Where the clip view is when the start of the lines shows. The gutter floats over the clip
    /// view and insets it, so this is left of zero.
    static func lineStartX(of scrollView: NSScrollView) -> CGFloat {
        -scrollView.contentView.contentInsets.left
    }

    /// The width available for text, next to the gutter.
    static func textWidth(of scrollView: NSScrollView) -> CGFloat {
        let clip = scrollView.contentView
        return clip.bounds.width - clip.contentInsets.left - clip.contentInsets.right
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let separatorWidth: CGFloat = 1
        let leftWidth = floor((bounds.width - separatorWidth) / 2)
        leftScrollView.frame = NSRect(x: 0, y: 0, width: leftWidth, height: bounds.height)
        separator.frame = NSRect(x: leftWidth, y: 0, width: separatorWidth, height: bounds.height)
        rightScrollView.frame = NSRect(
            x: leftWidth + separatorWidth,
            y: 0,
            width: bounds.width - leftWidth - separatorWidth,
            height: bounds.height
        )
        resizeColumns()
    }

    /// Each side as wide as its longest line (at least what's visible); both as tall as all the rows.
    private func resizeColumns() {
        let height = CGFloat(rowCount) * DiffLayout.rowHeight
        for (scrollView, column, longest) in [
            (leftScrollView, leftColumn, longestLines.left),
            (rightScrollView, rightColumn, longestLines.right),
        ] {
            let width = DiffLayout.documentWidth(longestLine: longest, visibleWidth: Self.textWidth(of: scrollView))
            column.setFrameSize(NSSize(width: width, height: height))
        }
    }

    // MARK: Linked vertical scrolling

    @objc private func clipViewDidScroll(_ notification: Notification) {
        leftGutter?.needsDisplay = true
        rightGutter?.needsDisplay = true
        guard !isFollowing, let source = notification.object as? NSClipView else { return }
        let follower = source === leftScrollView.contentView ? rightScrollView : leftScrollView
        let y = source.bounds.origin.y
        guard follower.contentView.bounds.origin.y != y else { return }
        isFollowing = true
        defer { isFollowing = false }
        follower.contentView.scroll(to: NSPoint(x: follower.contentView.bounds.origin.x, y: y))
        follower.reflectScrolledClipView(follower.contentView)
    }
}
