//
//  ScrollSync.swift
//  LF-Paper
//

import Foundation
import Observation

/// Where the editor and the Markdown preview should scroll to follow each other.
/// Two separate targets, so the editor only updates when the preview scrolls and vice versa.
@Observable
final class ScrollSync {
    nonisolated struct PreviewTarget: Equatable, Sendable {
        let id = UUID()
        let documentID: UUID
        /// Fractional, 1-based source line to bring to the top.
        let line: Double
    }

    private struct EditorTarget: Equatable {
        let documentID: UUID
        let request: EditorScrollRequest
    }

    private var previewTarget: PreviewTarget?
    private var editorTarget: EditorTarget?

    func previewTarget(for documentID: UUID) -> PreviewTarget? {
        previewTarget?.documentID == documentID ? previewTarget : nil
    }

    func editorRequest(for documentID: UUID) -> EditorScrollRequest? {
        editorTarget?.documentID == documentID ? editorTarget?.request : nil
    }

    func scrollPreview(toLine line: Double, in documentID: UUID) {
        previewTarget = PreviewTarget(documentID: documentID, line: line)
    }

    func scrollEditor(toLine line: Double, in documentID: UUID) {
        editorTarget = EditorTarget(documentID: documentID, request: EditorScrollRequest(line: line))
    }
}
