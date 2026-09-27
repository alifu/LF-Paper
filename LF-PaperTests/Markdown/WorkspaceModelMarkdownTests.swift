//
//  WorkspaceModelMarkdownTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

/// Scroll sync between the editor and the preview, and jumping to a heading from the outline.
@MainActor
struct WorkspaceModelMarkdownTests {
    private let workspace: TestWorkspace

    init() throws {
        workspace = try TestWorkspace(files: [
            "notes.md": "# Title\n\nIntro 😀.\n\n## Details\n\nMore.\n",
            "data.json": "{}",
        ])
        try workspace.open("notes.md")
    }

    private var model: WorkspaceModel { workspace.model }

    @Test func editorScrollingMovesThePreview() throws {
        let id = try #require(model.document?.id)

        model.editorDidScroll(toLine: 5.5, in: id)

        #expect(model.scrollSync.previewTarget(for: id)?.line == 5.5)
        #expect(model.scrollSync.editorRequest(for: id) == nil)
    }

    @Test func previewScrollingMovesTheEditor() throws {
        let id = try #require(model.document?.id)

        model.previewDidScroll(toLine: 3, in: id)

        #expect(model.scrollSync.editorRequest(for: id)?.line == 3)
        #expect(model.scrollSync.previewTarget(for: id) == nil)
    }

    @Test func onlyMarkdownWithBothPanesShowingIsSynced() throws {
        model.editorLayout = .editor
        let id = try #require(model.document?.id)
        model.editorDidScroll(toLine: 5, in: id)
        #expect(model.scrollSync.previewTarget(for: id) == nil)

        model.editorLayout = .split
        try workspace.open("data.json")
        let jsonID = try #require(model.document?.id)
        model.editorDidScroll(toLine: 5, in: jsonID)
        #expect(model.scrollSync.previewTarget(for: jsonID) == nil)
    }

    @Test func scrollingAnotherDocumentIsIgnored() throws {
        let id = try #require(model.document?.id)

        model.editorDidScroll(toLine: 5, in: UUID()) // a tab that isn't showing any more

        #expect(model.scrollSync.previewTarget(for: id) == nil)
    }

    @Test func choosingAHeadingMovesTheEditorCursorAndThePreview() throws {
        let id = try #require(model.document?.id)
        let details = MarkdownHeading(level: 2, title: "Details", line: 5)

        model.show(details)

        #expect(model.scrollSync.editorRequest(for: id)?.line == 5)
        #expect(model.scrollSync.previewTarget(for: id)?.line == 5)
        // Line 5 starts after "# Title\n\nIntro 😀.\n\n": UTF-16 offset 20 (the emoji counts 2).
        #expect(model.revealRequest?.range == NSRange(location: 20, length: 0))
        #expect(model.revealRequest?.focusesEditor == true)
    }

    @Test func choosingAHeadingInPreviewOnlyMovesThePreview() throws {
        model.editorLayout = .preview
        let id = try #require(model.document?.id)

        model.show(MarkdownHeading(level: 1, title: "Title", line: 1))

        #expect(model.scrollSync.previewTarget(for: id)?.line == 1)
    }
}
