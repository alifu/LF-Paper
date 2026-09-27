//
//  WorkspaceModel+Markdown.swift
//  LF-Paper
//

import Foundation

/// Markdown tools: the editor and preview scrolling together, and jumping to a heading.
extension WorkspaceModel {
    var isMarkdownDocument: Bool {
        document.map { FileKind(fileExtension: $0.url.pathExtension) == .markdown } ?? false
    }

    /// The editor and preview follow each other only when both show the active Markdown file.
    private var syncsScrolling: Bool {
        isMarkdownDocument && editorLayout.showsEditor && editorLayout.showsPreview
    }

    func editorDidScroll(toLine line: Double, in documentID: UUID) {
        guard syncsScrolling, document?.id == documentID else { return }
        scrollSync.scrollPreview(toLine: line, in: documentID)
    }

    func previewDidScroll(toLine line: Double, in documentID: UUID) {
        guard syncsScrolling, document?.id == documentID else { return }
        scrollSync.scrollEditor(toLine: line, in: documentID)
    }

    /// Outline › heading: the cursor goes to the heading, which scrolls to the top of the editor
    /// and of the preview.
    func show(_ heading: MarkdownHeading) {
        guard let document else { return }
        let line = Double(heading.line)
        if editorLayout.showsEditor {
            let starts = LineIndex(text: document.text as NSString).lineStarts
            let start = starts[min(max(heading.line - 1, 0), starts.count - 1)]
            reveal(NSRange(location: start, length: 0), focusesEditor: true, highlights: false)
            scrollSync.scrollEditor(toLine: line, in: document.id)
        }
        if editorLayout.showsPreview {
            scrollSync.scrollPreview(toLine: line, in: document.id)
        }
    }
}
