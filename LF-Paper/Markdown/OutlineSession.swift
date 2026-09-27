//
//  OutlineSession.swift
//  LF-Paper
//

import Foundation
import Observation

/// The headings of the Markdown file being edited, read in the background for the Outline sidebar.
@Observable
final class OutlineSession {
    /// Pause after typing before reading the headings again.
    static let refreshDelay: Duration = .milliseconds(250)

    private(set) var headings: [MarkdownHeading] = []
    /// The document the headings belong to; `nil` before the first read.
    private(set) var documentID: UUID?

    /// The headings for this document, or `nil` while they haven't been read yet
    /// (so the outline doesn't flash "No Headings").
    func headings(for documentID: UUID) -> [MarkdownHeading]? {
        self.documentID == documentID ? headings : nil
    }

    /// Re-reads the headings. For the same document it waits briefly first, so fast typing
    /// doesn't parse on every keystroke; a newer call cancels this one.
    func refresh(_ markdown: String, documentID: UUID) async {
        if self.documentID == documentID {
            try? await Task.sleep(for: Self.refreshDelay)
        }
        guard !Task.isCancelled else { return }
        let found = await MarkdownOutline.headingsInBackground(markdown)
        guard !Task.isCancelled else { return }
        headings = found
        self.documentID = documentID
    }
}
