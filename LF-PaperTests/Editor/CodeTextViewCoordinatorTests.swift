//
//  CodeTextViewCoordinatorTests.swift
//  LF-PaperTests
//

import AppKit
import Testing
@testable import LF_Paper

/// Drives the editor's coordinator against the same (window-less) views the app uses.
@MainActor
final class CodeTextViewCoordinatorTests {
    private static let editorSize = NSSize(width: 600, height: 400)

    private let scrollView: NSScrollView
    private let textView: NSTextView
    private var reportedTexts: [String] = []
    private lazy var coordinator = CodeTextView.Coordinator { [unowned self] in reportedTexts.append($0) }

    init() {
        let views = CodeTextView.makeEditorViews()
        scrollView = views.scrollView
        textView = views.textView
        scrollView.frame = NSRect(origin: .zero, size: Self.editorSize) // what SwiftUI does when it lays out the pane
        coordinator.attach(textView: views.textView, ruler: views.ruler)
    }

    // MARK: Visibility (regression: the text container was 0 pt tall, so no text was ever drawn)

    @Test func loadedTextIsLaidOutInsideTheVisibleEditor() throws {
        coordinator.update(text: "line one\nline two\nline three", documentID: UUID(), fileKind: nil)
        let layoutManager = try #require(textView.layoutManager)
        let textContainer = try #require(textView.textContainer)

        layoutManager.ensureLayout(for: textContainer)

        #expect(textView.frame.width > 0)
        #expect(layoutManager.glyphRange(for: textContainer).length == layoutManager.numberOfGlyphs)
        #expect(layoutManager.usedRect(for: textContainer).height > 0)
    }

    @Test func textContainerIsTallEnoughForLongDocuments() throws {
        let longText = (1...500).map { "line \($0)" }.joined(separator: "\n")
        coordinator.update(text: longText, documentID: UUID(), fileKind: nil)
        let layoutManager = try #require(textView.layoutManager)
        let textContainer = try #require(textView.textContainer)

        layoutManager.ensureLayout(for: textContainer)

        #expect(layoutManager.glyphRange(for: textContainer).length == layoutManager.numberOfGlyphs)
        #expect(textView.frame.height > Self.editorSize.height) // grows so the scroll view can scroll
    }

    private func type(_ text: String) {
        let end = NSRange(location: (textView.string as NSString).length, length: 0)
        textView.insertText(text, replacementRange: end)
    }

    @Test func loadingADocumentShowsItsTextWithoutReportingAnEdit() {
        coordinator.update(text: "# Hello", documentID: UUID(), fileKind: .markdown)

        #expect(textView.string == "# Hello")
        #expect(reportedTexts.isEmpty)
    }

    @Test func typingReportsTheNewText() {
        coordinator.update(text: "a", documentID: UUID(), fileKind: .markdown)

        type("b")

        #expect(reportedTexts == ["ab"])
    }

    @Test func sameDocumentWithSameTextKeepsUndoHistory() {
        let id = UUID()
        coordinator.update(text: "a", documentID: id, fileKind: .markdown)
        let undoBefore = coordinator.undoManager(for: textView)

        type("b")
        coordinator.update(text: "ab", documentID: id, fileKind: .markdown) // model echoes the edit

        #expect(coordinator.undoManager(for: textView) === undoBefore)
        #expect(reportedTexts == ["ab"])
    }

    @Test func switchingDocumentsStartsAFreshUndoHistory() {
        coordinator.update(text: "a", documentID: UUID(), fileKind: .markdown)
        let firstUndo = coordinator.undoManager(for: textView)

        coordinator.update(text: "other", documentID: UUID(), fileKind: .json)

        #expect(textView.string == "other")
        #expect(coordinator.undoManager(for: textView) !== firstUndo)
    }

    @Test func switchingBackToADocumentRestoresItsUndoHistoryAndSelection() {
        let first = UUID()
        coordinator.update(text: "first", documentID: first, fileKind: nil)
        let firstUndo = coordinator.undoManager(for: textView)
        textView.setSelectedRange(NSRange(location: 2, length: 3))

        coordinator.update(text: "second", documentID: UUID(), fileKind: nil)
        coordinator.update(text: "first", documentID: first, fileKind: nil)

        #expect(coordinator.undoManager(for: textView) === firstUndo)
        #expect(textView.selectedRange() == NSRange(location: 2, length: 3))
    }

    @Test func closedDocumentsForgetTheirUndoHistory() {
        let first = UUID()
        let second = UUID()
        coordinator.update(text: "first", documentID: first, fileKind: nil)
        let firstUndo = coordinator.undoManager(for: textView)

        coordinator.update(text: "second", documentID: second, fileKind: nil, openDocumentIDs: [second])
        coordinator.update(text: "first", documentID: first, fileKind: nil)

        #expect(coordinator.undoManager(for: textView) !== firstUndo)
    }

    // MARK: Scroll sync

    private static let manyLines = (1...300).map { "Line \($0) of the document." }.joined(separator: "\n")

    private func scrollEditor(toY y: CGFloat) throws {
        let clip = try #require(textView.enclosingScrollView?.contentView)
        clip.scroll(to: NSPoint(x: 0, y: y))
        textView.enclosingScrollView?.reflectScrolledClipView(clip)
    }

    @Test func reportsTheTopVisibleLineWhenScrolled() throws {
        var reported: [(UUID, Double)] = []
        coordinator.onScrollLine = { reported.append(($0, $1)) }
        let id = UUID()
        coordinator.update(text: Self.manyLines, documentID: id, fileKind: .markdown)
        let lineHeight = try #require(textView.layoutManager?.defaultLineHeight(for: textView.font!))

        try scrollEditor(toY: textView.textContainerOrigin.y + 49.5 * lineHeight)

        let last = try #require(reported.last)
        #expect(last.0 == id)
        #expect(abs(last.1 - 50.5) < 0.2, "top line \(last.1)")
    }

    @Test func scrollRequestsPutTheLineAtTheTopWithoutEchoing() throws {
        var reported: [Double] = []
        coordinator.onScrollLine = { reported.append($1) }
        coordinator.update(text: Self.manyLines, documentID: UUID(), fileKind: .markdown)

        coordinator.update(text: Self.manyLines, documentID: coordinator.currentDocumentID!, fileKind: .markdown, scrollRequest: EditorScrollRequest(line: 120))

        // AppKit may re-tile and report where the text was; the requested line itself never echoes back.
        #expect(!reported.contains { $0 > 2 }, "a requested scroll isn't reported back: \(reported)")
        let top = try #require(coordinator.topVisibleLine())
        #expect(abs(top - 120) < 0.2, "top line \(top)")
    }

    @Test func eachScrollRequestIsAppliedOnce() throws {
        let request = EditorScrollRequest(line: 80)
        coordinator.update(text: Self.manyLines, documentID: UUID(), fileKind: .markdown, scrollRequest: request)
        try scrollEditor(toY: 0)

        coordinator.update(text: Self.manyLines, documentID: coordinator.currentDocumentID!, fileKind: .markdown, scrollRequest: request)

        #expect(try #require(coordinator.topVisibleLine()) < 2)
    }

    @Test func anEmptyDocumentIsAtLineOne() {
        coordinator.update(text: "", documentID: UUID(), fileKind: .markdown)

        #expect(coordinator.topVisibleLine() == 1)
    }

    // MARK: Line wrapping

    private static let longLine = String(repeating: "wide ", count: 400)

    private func usedWidth() throws -> CGFloat {
        let layoutManager = try #require(textView.layoutManager)
        let textContainer = try #require(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        return layoutManager.usedRect(for: textContainer).width
    }

    @Test func withoutWrappingLongLinesScrollSideways() throws {
        coordinator.update(text: Self.longLine, documentID: UUID(), fileKind: nil, wrapsLines: false)

        #expect(scrollView.hasHorizontalScroller)
        #expect(textView.isHorizontallyResizable)
        #expect(textView.textContainer?.widthTracksTextView == false)
        #expect(try usedWidth() > Self.editorSize.width)
        #expect(textView.frame.width > Self.editorSize.width) // wide enough to scroll to the end of the line
    }

    @Test func wrappingKeepsLinesWithinTheEditor() throws {
        coordinator.update(text: Self.longLine, documentID: UUID(), fileKind: nil, wrapsLines: true)

        #expect(!scrollView.hasHorizontalScroller)
        #expect(textView.textContainer?.widthTracksTextView == true)
        #expect(try usedWidth() <= Self.editorSize.width)
    }

    @Test func switchingWrappingBackAndForthReflowsTheText() throws {
        let id = UUID()
        coordinator.update(text: Self.longLine, documentID: id, fileKind: nil, wrapsLines: false)
        coordinator.update(text: Self.longLine, documentID: id, fileKind: nil, wrapsLines: true)

        #expect(try usedWidth() <= Self.editorSize.width)
        #expect(textView.frame.width <= Self.editorSize.width)

        coordinator.update(text: Self.longLine, documentID: id, fileKind: nil, wrapsLines: false)
        #expect(try usedWidth() > Self.editorSize.width)
    }

    @Test func reportsSelectionChangesWithTheirDocument() {
        var reported: [(UUID, NSRange)] = []
        coordinator.onSelectionChange = { reported.append(($0, $1)) }
        let id = UUID()
        coordinator.update(text: "hello world", documentID: id, fileKind: nil)

        textView.setSelectedRange(NSRange(location: 6, length: 5))

        #expect(reported.last?.0 == id)
        #expect(reported.last?.1 == NSRange(location: 6, length: 5))
    }

    @Test func switchingBetweenTheScratchpadAndAFileKeepsBothUndoHistories() throws {
        let folder = try TemporaryDirectory()
        try folder.makeFile("a.md", contents: "A")
        let suiteName = "LFPaperTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let model = WorkspaceModel(
            bookmarkStore: BookmarkStore(defaults: defaults),
            recentFolders: RecentFolders(defaults: defaults),
            watchesFileSystem: false
        )
        model.openFolder(folder.url)
        model.selection = try #require(model.children(of: folder.url).first).url
        let file = try #require(model.document)

        coordinator.update(text: file.text, documentID: file.id, fileKind: .markdown, openDocumentIDs: model.editorDocumentIDs)
        let fileUndo = coordinator.undoManager(for: textView)
        model.showScratchpad()
        coordinator.update(text: model.scratchpadText, documentID: model.scratchpadID, fileKind: nil, openDocumentIDs: model.editorDocumentIDs)
        let scratchpadUndo = coordinator.undoManager(for: textView)
        model.toggleScratchpad()
        coordinator.update(text: file.text, documentID: file.id, fileKind: .markdown, openDocumentIDs: model.editorDocumentIDs)
        #expect(coordinator.undoManager(for: textView) === fileUndo)

        model.toggleScratchpad()
        coordinator.update(text: model.scratchpadText, documentID: model.scratchpadID, fileKind: nil, openDocumentIDs: model.editorDocumentIDs)
        #expect(coordinator.undoManager(for: textView) === scratchpadUndo)
    }

    @Test func changingTheFontSizeRestylesAllText() throws {
        let id = UUID()
        coordinator.update(text: "# Title\nplain", documentID: id, fileKind: .markdown)

        coordinator.update(text: "# Title\nplain", documentID: id, fileKind: .markdown, fontSize: 18)

        let storage = try #require(textView.textStorage)
        for index in 0..<storage.length {
            let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
            #expect(font?.pointSize == 18, "font size at \(index)")
        }
        #expect((textView.typingAttributes[.font] as? NSFont)?.pointSize == 18)
    }

    // MARK: Appearance (regression: loaded text had no attributes and drew black in dark mode)

    /// Every character uses the theme's font and the appearance-adaptive text color.
    private func expectThemeStyleEverywhere(sourceLocation: SourceLocation = #_sourceLocation) {
        let storage = textView.textStorage!
        let theme = EditorTheme.standard
        for index in 0..<storage.length {
            let color = storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
            let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
            #expect(color == NSColor.textColor, "color at \(index)", sourceLocation: sourceLocation)
            #expect(font == theme.font, "font at \(index)", sourceLocation: sourceLocation)
        }
    }

    @Test func loadedTextUsesTheAdaptiveTextColorAndThemeFont() {
        coordinator.update(text: "line one\nline two", documentID: UUID(), fileKind: nil)

        expectThemeStyleEverywhere()
    }

    @Test func typedTextUsesTheAdaptiveTextColorAndThemeFont() {
        coordinator.update(text: "loaded", documentID: UUID(), fileKind: nil)
        textView.setSelectedRange(NSRange(location: 6, length: 0))

        type(" typed")

        expectThemeStyleEverywhere()
    }

    @Test func reloadedTextUsesTheAdaptiveTextColorAndThemeFont() {
        let id = UUID()
        coordinator.update(text: "old", documentID: id, fileKind: nil)

        coordinator.update(text: "reloaded", documentID: id, fileKind: nil)

        expectThemeStyleEverywhere()
    }

    @Test func markdownFilesAreHighlighted() throws {
        coordinator.update(text: "# Title\nplain", documentID: UUID(), fileKind: .markdown)
        let storage = try #require(textView.textStorage)

        let headingColor = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let plainColor = storage.attribute(.foregroundColor, at: 9, effectiveRange: nil) as? NSColor

        #expect(headingColor == EditorTheme.standard.attributes(for: .heading)[.foregroundColor] as? NSColor)
        #expect(plainColor == NSColor.textColor)
    }

    @Test func changesFromOutsideTheSameDocumentCanBeUndone() throws {
        let id = UUID()
        coordinator.update(text: "old", documentID: id, fileKind: nil)

        coordinator.update(text: "formatted", documentID: id, fileKind: nil)
        RunLoop.main.run(until: Date()) // closes the undo group, as the event loop would
        let undoManager = try #require(coordinator.undoManager(for: textView))

        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(textView.string == "old")
    }

    // MARK: Revealing

    @Test func revealRequestSelectsTheRange() {
        let request = RevealRequest(range: NSRange(location: 2, length: 3), focusesEditor: false)

        coordinator.update(text: "0123456789", documentID: UUID(), fileKind: nil, revealRequest: request)

        #expect(textView.selectedRange() == NSRange(location: 2, length: 3))
    }

    @Test func revealRangesAreClampedToTheText() {
        let request = RevealRequest(range: NSRange(location: 8, length: 10), focusesEditor: false)

        coordinator.update(text: "0123456789", documentID: UUID(), fileKind: nil, revealRequest: request)

        #expect(textView.selectedRange() == NSRange(location: 8, length: 2))
    }

    @Test func theSameRevealRequestIsAppliedOnlyOnce() {
        let id = UUID()
        let request = RevealRequest(range: NSRange(location: 2, length: 3), focusesEditor: false)
        coordinator.update(text: "0123456789", documentID: id, fileKind: nil, revealRequest: request)
        textView.setSelectedRange(NSRange(location: 0, length: 0)) // the user moves on

        coordinator.update(text: "0123456789", documentID: id, fileKind: nil, revealRequest: request)

        #expect(textView.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test func textChangedOutsideTheEditorIsLoaded() {
        let id = UUID()
        coordinator.update(text: "old", documentID: id, fileKind: .markdown)

        coordinator.update(text: "reloaded from disk", documentID: id, fileKind: .markdown)

        #expect(textView.string == "reloaded from disk")
        #expect(reportedTexts.isEmpty)
    }
}
