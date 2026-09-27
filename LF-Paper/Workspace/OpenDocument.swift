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
    let savedText: String
    /// A file that doesn't exist yet (such as a conversion result); saving creates it.
    let isNew: Bool

    init(url: URL, text: String) {
        self.init(id: UUID(), url: url, text: text, savedText: text, isNew: false)
    }

    /// A new file at `url` holding `text`; it counts as unsaved until it's saved.
    static func newFile(at url: URL, text: String) -> OpenDocument {
        OpenDocument(id: UUID(), url: url, text: text, savedText: "", isNew: true)
    }

    private init(id: UUID, url: URL, text: String, savedText: String, isNew: Bool) {
        self.id = id
        self.url = url
        self.text = text
        self.savedText = savedText
        self.isNew = isNew
    }

    var isDirty: Bool { isNew || text != savedText }

    func editing(_ newText: String) -> OpenDocument {
        OpenDocument(id: id, url: url, text: newText, savedText: savedText, isNew: isNew)
    }

    func moving(to newURL: URL) -> OpenDocument {
        OpenDocument(id: id, url: newURL, text: text, savedText: savedText, isNew: isNew)
    }

    func markingSaved() -> OpenDocument {
        OpenDocument(id: id, url: url, text: text, savedText: text, isNew: false)
    }

    func reverted() -> OpenDocument {
        OpenDocument(id: id, url: url, text: savedText, savedText: savedText, isNew: isNew)
    }
}
