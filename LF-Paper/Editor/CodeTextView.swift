//
//  CodeTextView.swift
//  LF-Paper
//

import AppKit
import SwiftUI

/// Plain-text code editor on a TextKit 1 `NSTextView`: monospaced, line numbers, find bar,
/// a separate undo history per document, and syntax highlighting of the lines being edited.
struct CodeTextView: NSViewRepresentable {
    let text: String
    /// Changing this loads `text` as a new document and starts a fresh undo history.
    let documentID: UUID
    let fileKind: FileKind?
    let onTextChange: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChange: onTextChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let views = Self.makeEditorViews()
        context.coordinator.attach(textView: views.textView, ruler: views.ruler)
        context.coordinator.update(text: text, documentID: documentID, fileKind: fileKind)
        return views.scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onTextChange = onTextChange
        context.coordinator.update(text: text, documentID: documentID, fileKind: fileKind)
    }

    /// The scroll view, text view and line-number ruler, configured and connected.
    /// Internal (not private) so tests exercise exactly what the app shows.
    static func makeEditorViews() -> (scrollView: NSScrollView, textView: NSTextView, ruler: LineNumberRulerView) {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        let textView = makeTextView()
        scrollView.documentView = textView

        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        return (scrollView, textView, ruler)
    }

    private static func makeTextView() -> NSTextView {
        let textView = NSTextView(usingTextLayoutManager: false)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 4, height: 8)

        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false

        let theme = EditorTheme.standard
        textView.font = theme.font
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.typingAttributes = theme.baseAttributes
        return textView
    }
}

extension CodeTextView {
    final class Coordinator: NSObject, NSTextViewDelegate {
        /// Bigger documents are shown as plain text so typing stays responsive.
        private static let highlightingLimit = 2_000_000

        var onTextChange: @MainActor (String) -> Void
        private weak var textView: NSTextView?
        private weak var ruler: LineNumberRulerView?
        private var documentID: UUID?
        private var fileKind: FileKind?
        private var highlighter: (any SyntaxHighlighter)?
        private var undoManager = UndoManager()
        private var isReplacingText = false
        private let theme = EditorTheme.standard

        init(onTextChange: @escaping @MainActor (String) -> Void) {
            self.onTextChange = onTextChange
        }

        func attach(textView: NSTextView, ruler: LineNumberRulerView) {
            self.textView = textView
            self.ruler = ruler
            textView.delegate = self
            textView.textStorage?.delegate = self
        }

        /// Loads text only for a new document or when the text changed outside the editor
        /// (e.g. reloaded from disk). Typing reaches the model through `textDidChange` instead.
        func update(text: String, documentID: UUID, fileKind: FileKind?) {
            guard let textView else { return }
            let isNewDocument = documentID != self.documentID
            let isNewKind = fileKind != self.fileKind
            self.documentID = documentID
            self.fileKind = fileKind
            if isNewKind {
                highlighter = SyntaxHighlighters.highlighter(for: fileKind)
            }

            if isNewDocument || textView.string != text {
                replaceText(in: textView, with: text)
                if isNewDocument {
                    textView.setSelectedRange(NSRange(location: 0, length: 0))
                    textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
                }
            } else if isNewKind, let storage = textView.textStorage {
                // Renamed to another file type: same text, different highlighting.
                applyStyle(to: NSRange(location: 0, length: storage.length), in: storage)
            }
        }

        private func replaceText(in textView: NSTextView, with text: String) {
            // Old undo steps refer to text that is no longer there.
            undoManager = UndoManager()
            isReplacingText = true
            textView.string = text
            isReplacingText = false
            // Typing takes its style from the text at the cursor; start from the theme, not stale styles.
            textView.typingAttributes = theme.baseAttributes
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            undoManager
        }

        func textDidChange(_ notification: Notification) {
            guard !isReplacingText, let textView else { return }
            onTextChange(textView.string)
        }

        /// Resets the edited lines to the theme's font and appearance-adaptive color, then
        /// highlights them. Text inserted programmatically arrives with no attributes at all,
        /// which would draw as black 12 pt Helvetica — unreadable in dark mode.
        fileprivate func applyStyle(to editedRange: NSRange, in storage: NSTextStorage) {
            let text = storage.mutableString
            let shouldHighlight = highlighter != nil && storage.length <= Self.highlightingLimit
            let range = shouldHighlight
                ? highlighter?.invalidationRange(for: editedRange, in: text) ?? editedRange
                : TextRanges.lines(touching: editedRange, in: text)
            storage.setAttributes(theme.baseAttributes, range: range)

            guard shouldHighlight, let highlighter else { return }
            for token in highlighter.tokens(in: text, range: range) {
                storage.addAttributes(theme.attributes(for: token.kind), range: token.range)
            }
        }
    }
}

extension CodeTextView.Coordinator: @preconcurrency NSTextStorageDelegate {
    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        ruler?.textDidChange()
        applyStyle(to: editedRange, in: textStorage)
    }
}
