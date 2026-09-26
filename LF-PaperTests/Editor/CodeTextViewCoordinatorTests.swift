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

    @Test func textChangedOutsideTheEditorIsLoaded() {
        let id = UUID()
        coordinator.update(text: "old", documentID: id, fileKind: .markdown)

        coordinator.update(text: "reloaded from disk", documentID: id, fileKind: .markdown)

        #expect(textView.string == "reloaded from disk")
        #expect(reportedTexts.isEmpty)
    }
}
