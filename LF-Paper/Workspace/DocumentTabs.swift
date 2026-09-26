//
//  DocumentTabs.swift
//  LF-Paper
//

import Foundation

/// The open files of a workspace, in tab order, and which one is showing.
/// Immutable: every change returns a new value.
nonisolated struct DocumentTabs: Equatable, Sendable {
    static let empty = DocumentTabs(documents: [], activeID: nil, missingOnDisk: [])

    let documents: [OpenDocument]
    let activeID: UUID?
    /// Documents whose file was deleted on disk while they had unsaved changes. Saving recreates them.
    let missingOnDisk: Set<UUID>

    var active: OpenDocument? {
        activeID.flatMap(document(withID:))
    }

    var hasUnsavedChanges: Bool {
        documents.contains { hasUnsavedChanges($0.id) }
    }

    func hasUnsavedChanges(_ id: UUID) -> Bool {
        missingOnDisk.contains(id) || document(withID: id)?.isDirty == true
    }

    func document(withID id: UUID) -> OpenDocument? {
        documents.first { $0.id == id }
    }

    func document(at url: URL) -> OpenDocument? {
        documents.first { $0.url.refersToSameFile(as: url) }
    }

    /// Adds a tab just after the active one and shows it.
    func opening(_ document: OpenDocument) -> DocumentTabs {
        let insertion = activeIndex.map { $0 + 1 } ?? documents.endIndex
        var reordered = documents
        reordered.insert(document, at: insertion)
        return DocumentTabs(documents: reordered, activeID: document.id, missingOnDisk: missingOnDisk)
    }

    func activating(_ id: UUID) -> DocumentTabs {
        guard document(withID: id) != nil else { return self }
        return DocumentTabs(documents: documents, activeID: id, missingOnDisk: missingOnDisk)
    }

    /// Replaces the document with the same id (an edit, save, rename or revert).
    func replacing(_ document: OpenDocument) -> DocumentTabs {
        DocumentTabs(
            documents: documents.map { $0.id == document.id ? document : $0 },
            activeID: activeID,
            missingOnDisk: missingOnDisk
        )
    }

    /// Replaces a document with a freshly loaded one (a new id), keeping its place and active state.
    func reloading(_ id: UUID, with document: OpenDocument) -> DocumentTabs {
        DocumentTabs(
            documents: documents.map { $0.id == id ? document : $0 },
            activeID: activeID == id ? document.id : activeID,
            missingOnDisk: missingOnDisk.subtracting([id])
        )
    }

    /// Removes a tab. Closing the active tab shows its right neighbour, or else its left one.
    func closing(_ id: UUID) -> DocumentTabs {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return self }
        let remaining = documents.filter { $0.id != id }
        let nextActive = activeID == id
            ? remaining[safe: index]?.id ?? remaining[safe: index - 1]?.id
            : activeID
        return DocumentTabs(documents: remaining, activeID: nextActive, missingOnDisk: missingOnDisk.subtracting([id]))
    }

    func marking(_ id: UUID, missingOnDisk isMissing: Bool) -> DocumentTabs {
        let missing = isMissing ? missingOnDisk.union([id]) : missingOnDisk.subtracting([id])
        return DocumentTabs(documents: documents, activeID: activeID, missingOnDisk: missing)
    }

    /// The tab `offset` places from the active one, wrapping around the ends.
    func neighbour(offset: Int) -> UUID? {
        guard let activeIndex, !documents.isEmpty else { return nil }
        let count = documents.count
        return documents[((activeIndex + offset) % count + count) % count].id
    }

    private var activeIndex: Int? {
        documents.firstIndex { $0.id == activeID }
    }
}

private extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension URL {
    /// Whether both URLs name the same path, ignoring spelling differences such as a trailing slash.
    nonisolated func refersToSameFile(as other: URL) -> Bool {
        standardizedFileURL.pathComponents == other.standardizedFileURL.pathComponents
    }
}
