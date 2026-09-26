//
//  CodeTextView.swift
//  LF-Paper
//

import AppKit
import SwiftUI

/// Plain-text code editor on a TextKit 1 `NSTextView`: monospaced, line numbers, find bar,
/// a separate undo history (and selection) per open document, and syntax highlighting of the lines being edited.
struct CodeTextView: NSViewRepresentable {
    let text: String
    /// Changing this loads `text` as another document, with that document's own undo history.
    let documentID: UUID
    let fileKind: FileKind?
    var fontSize: CGFloat = EditorTheme.defaultFontSize
    /// Documents still open in tabs; the undo histories of all others are dropped.
    var openDocumentIDs: Set<UUID>? = nil
    /// Selects and scrolls to a range once per request (e.g. a JSON error or a tree value).
    var revealRequest: RevealRequest?
    let onTextChange: @MainActor (String) -> Void
    /// The selection of the showing document, as it changes (for restoring tabs later).
    var onSelectionChange: @MainActor (UUID, NSRange) -> Void = { _, _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChange: onTextChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let views = Self.makeEditorViews()
        context.coordinator.attach(textView: views.textView, ruler: views.ruler)
        updateCoordinator(context.coordinator)
        return views.scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onSelectionChange = onSelectionChange
        updateCoordinator(context.coordinator)
    }

    private func updateCoordinator(_ coordinator: Coordinator) {
        coordinator.update(
            text: text,
            documentID: documentID,
            fileKind: fileKind,
            revealRequest: revealRequest,
            fontSize: fontSize,
            openDocumentIDs: openDocumentIDs
        )
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
        textView.setAccessibilityIdentifier("editor")

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

        /// What's kept for a document while another tab is showing.
        private struct DocumentState {
            let undoManager: UndoManager
            let selectedRange: NSRange
        }

        var onTextChange: @MainActor (String) -> Void
        var onSelectionChange: @MainActor (UUID, NSRange) -> Void = { _, _ in }
        private weak var textView: NSTextView?
        private weak var ruler: LineNumberRulerView?
        private var documentID: UUID?
        private var fileKind: FileKind?
        private var highlighter: (any SyntaxHighlighter)?
        private var undoManager = UndoManager()
        private var savedStates: [UUID: DocumentState] = [:]
        private var isReplacingText = false
        private var lastRevealID: UUID?
        private var theme = EditorTheme.standard

        init(onTextChange: @escaping @MainActor (String) -> Void) {
            self.onTextChange = onTextChange
        }

        func attach(textView: NSTextView, ruler: LineNumberRulerView) {
            self.textView = textView
            self.ruler = ruler
            textView.delegate = self
            textView.textStorage?.delegate = self
        }

        /// Loads text for another document (restoring its undo history and selection if it was shown
        /// before). For the same document, text changed outside the editor (Format, Minify, revert)
        /// is applied as an undoable edit. Typing reaches the model through `textDidChange` instead.
        func update(
            text: String,
            documentID: UUID,
            fileKind: FileKind?,
            revealRequest: RevealRequest? = nil,
            fontSize: CGFloat = EditorTheme.defaultFontSize,
            openDocumentIDs: Set<UUID>? = nil
        ) {
            guard let textView else { return }
            let isNewDocument = documentID != self.documentID
            let isNewKind = fileKind != self.fileKind
            let isNewFontSize = fontSize != theme.font.pointSize
            if isNewDocument, let previousID = self.documentID {
                savedStates[previousID] = DocumentState(undoManager: undoManager, selectedRange: textView.selectedRange())
            }
            if let openDocumentIDs {
                savedStates = savedStates.filter { openDocumentIDs.contains($0.key) }
            }
            self.documentID = documentID
            self.fileKind = fileKind
            if isNewKind {
                highlighter = SyntaxHighlighters.highlighter(for: fileKind)
            }
            if isNewFontSize {
                theme = EditorTheme(fontSize: fontSize)
                textView.font = theme.font
                textView.typingAttributes = theme.baseAttributes
                ruler?.matchEditorFontSize(fontSize)
            }

            if isNewDocument {
                show(text, restoring: savedStates.removeValue(forKey: documentID), in: textView)
            } else if textView.string != text {
                applyUndoableEdit(in: textView, replacingAllWith: text)
            } else if isNewKind || isNewFontSize, let storage = textView.textStorage {
                // Renamed to another file type, or a new font size: same text, restyled.
                applyStyle(to: NSRange(location: 0, length: storage.length), in: storage)
            }
            reveal(revealRequest, in: textView)
        }

        private func show(_ text: String, restoring state: DocumentState?, in textView: NSTextView) {
            replaceText(in: textView, with: text)
            undoManager = state?.undoManager ?? UndoManager()
            let selection = Self.clamped(state?.selectedRange ?? NSRange(location: 0, length: 0), toLength: (text as NSString).length)
            textView.setSelectedRange(selection)
            textView.scrollRangeToVisible(selection)
        }

        private func applyUndoableEdit(in textView: NSTextView, replacingAllWith text: String) {
            let everything = NSRange(location: 0, length: (textView.string as NSString).length)
            isReplacingText = true
            defer { isReplacingText = false }
            guard textView.shouldChangeText(in: everything, replacementString: text) else { return }
            textView.textStorage?.replaceCharacters(in: everything, with: text)
            textView.didChangeText()
            textView.typingAttributes = theme.baseAttributes
        }

        private func reveal(_ request: RevealRequest?, in textView: NSTextView) {
            guard let request, request.id != lastRevealID else { return }
            lastRevealID = request.id
            let range = Self.clamped(request.range, toLength: (textView.string as NSString).length)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            if request.focusesEditor {
                textView.window?.makeFirstResponder(textView)
            }
            if request.highlights, range.length > 0 {
                textView.showFindIndicator(for: range)
            }
        }

        private static func clamped(_ range: NSRange, toLength length: Int) -> NSRange {
            let location = min(max(range.location, 0), length)
            return NSRange(location: location, length: min(max(range.length, 0), length - location))
        }

        private func replaceText(in textView: NSTextView, with text: String) {
            isReplacingText = true
            textView.string = text
            isReplacingText = false
            // Typing takes its style from the text at the cursor; start from the theme, not stale styles.
            textView.typingAttributes = theme.baseAttributes
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            undoManager
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView, let documentID else { return }
            onSelectionChange(documentID, textView.selectedRange())
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
