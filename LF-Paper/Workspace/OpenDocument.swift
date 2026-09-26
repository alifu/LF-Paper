//
//  OpenDocument.swift
//  LF-Paper
//

import Foundation

/// An immutable snapshot of the file being edited. Each change returns a new value.
nonisolated struct OpenDocument: Equatable, Sendable {
    let url: URL
    let text: String
    /// The text as it is on disk, used to tell whether there are unsaved changes.
    private let savedText: String

    init(url: URL, text: String) {
        self.init(url: url, text: text, savedText: text)
    }

    private init(url: URL, text: String, savedText: String) {
        self.url = url
        self.text = text
        self.savedText = savedText
    }

    var isDirty: Bool { text != savedText }

    func editing(_ newText: String) -> OpenDocument {
        OpenDocument(url: url, text: newText, savedText: savedText)
    }

    func moving(to newURL: URL) -> OpenDocument {
        OpenDocument(url: newURL, text: text, savedText: savedText)
    }

    func markingSaved() -> OpenDocument {
        OpenDocument(url: url, text: text)
    }
}
