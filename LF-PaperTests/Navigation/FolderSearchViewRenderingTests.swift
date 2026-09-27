//
//  FolderSearchViewRenderingTests.swift
//  LF-PaperTests
//

import AppKit
import SwiftUI
import Testing
@testable import LF_Paper

/// Renders the sidebar's search mode with results offscreen, in dark and light mode.
@MainActor
struct FolderSearchViewRenderingTests {
    private static let size = NSSize(width: 280, height: 320)

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func showsMatchesGroupedByFile(appearance: NSAppearance.Name) async throws {
        let workspace = try TestWorkspace(files: [
            "README.md": "# Readme\nThe needle is here.\nAnother needle.",
            "data/config.json": #"{"needle": true}"#,
        ])
        workspace.model.search.text = "needle"
        workspace.model.runFolderSearch()
        await workspace.model.search.task?.value
        #expect(workspace.model.search.matchCount == 3)

        // The sidebar column draws the background in the app.
        let view = FolderSearchView(model: workspace.model).background(Color(nsColor: .windowBackgroundColor))
        let bitmap = try OffscreenRenderer.render(view, size: Self.size, appearance: appearance)
        try OffscreenRenderer.attach(bitmap, named: "folder-search-\(appearance.rawValue).png")

        let content = OffscreenRenderer.contentPixels(in: bitmap, appearance: appearance)
        let blank = try OffscreenRenderer.blankContentPixels(size: Self.size, appearance: appearance)
        #expect(content > blank + 150, "results should be visible (blank: \(blank), view: \(content))")
    }

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func showsTheReplaceFieldAndWhatReplaceAllDid(appearance: NSAppearance.Name) async throws {
        let workspace = try TestWorkspace(files: [
            "README.md": "The needle is here.",
            "notes.md": "needle",
        ])
        let model = workspace.model
        model.search.text = "needle"
        model.runFolderSearch()
        await model.search.task?.value
        model.showFolderReplace()
        model.replace.replacement = "thread"
        model.prepareReplaceAll()
        await model.replace.task?.value
        try "changed".write(to: workspace.folder.url.appending(path: "notes.md"), atomically: true, encoding: .utf8)
        model.applyReplaceAll()
        await model.search.task?.value
        #expect(model.replace.outcome?.skipped.count == 1)

        let view = FolderSearchView(model: model).background(Color(nsColor: .windowBackgroundColor))
        let bitmap = try OffscreenRenderer.render(view, size: Self.size, appearance: appearance)
        try OffscreenRenderer.attach(bitmap, named: "folder-replace-\(appearance.rawValue).png")

        let content = OffscreenRenderer.contentPixels(in: bitmap, appearance: appearance)
        let blank = try OffscreenRenderer.blankContentPixels(size: Self.size, appearance: appearance)
        #expect(content > blank + 150, "the Replace field and outcome should be visible (blank: \(blank), view: \(content))")
    }

    @Test func summaryCountsMatchesAndFiles() {
        #expect(FolderSearchView.summary(matches: 0, files: 0, searched: "x", isTruncated: false) == "No results for “x”")
        #expect(FolderSearchView.summary(matches: 1, files: 1, searched: "x", isTruncated: false) == "1 match in 1 file")
        #expect(FolderSearchView.summary(matches: 5, files: 2, searched: "x", isTruncated: false) == "5 matches in 2 files")
        #expect(FolderSearchView.summary(matches: 10, files: 3, searched: "x", isTruncated: true).hasSuffix("(stopped at 10; refine the search)"))
    }
}
