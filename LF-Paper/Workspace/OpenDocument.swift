//
//  OpenDocument.swift
//  LF-Paper
//

import Foundation

/// An immutable snapshot of the file being edited. Each change returns a new value.
nonisolated struct OpenDocument: Identifiable, Equatable, Sendable {
    /// Stays the same across edits, saves and renames; a freshly opened file gets a new one.
    /// The editor uses it to know when to reset its undo history.
    let id: UUID
    let url: URL
    let text: String
    /// The text as it is on disk, used to tell whether there are unsaved changes.
    private let savedText: String

    init(url: URL, text: String) {
        self.init(id: UUID(), url: url, text: text, savedText: text)
    }

    private init(id: UUID, url: URL, text: String, savedText: String) {
        self.id = id
        self.url = url
        self.text = text
        self.savedText = savedText
    }

    var isDirty: Bool { text != savedText }

    func editing(_ newText: String) -> OpenDocument {
        OpenDocument(id: id, url: url, text: newText, savedText: savedText)
    }

    func moving(to newURL: URL) -> OpenDocument {
        OpenDocument(id: id, url: newURL, text: text, savedText: savedText)
    }

    func markingSaved() -> OpenDocument {
        OpenDocument(id: id, url: url, text: text, savedText: text)
    }

    func reverted() -> OpenDocument {
        OpenDocument(id: id, url: url, text: savedText, savedText: savedText)
    }
}
