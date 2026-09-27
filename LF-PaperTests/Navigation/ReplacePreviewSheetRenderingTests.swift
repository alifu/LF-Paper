//
//  ReplacePreviewSheetRenderingTests.swift
//  LF-PaperTests
//

import AppKit
import SwiftUI
import Testing
@testable import LF_Paper

/// Renders the Replace All preview offscreen, in dark and light mode.
@MainActor
struct ReplacePreviewSheetRenderingTests {
    private static let size = NSSize(width: 640, height: 420)

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func showsEachFileWithItsChangesAndTheSkippedOnes(appearance: NSAppearance.Name) async throws {
        let workspace = try TestWorkspace(files: [
            "README.md": "# Readme\nThe cat sat on the mat.\nAnother cat.",
            "docs/guide.md": "  indented cat line",
            "data.json": #"{"cat": true}"#,
        ])
        let model = workspace.model
        model.search.text = "cat"
        model.runFolderSearch()
        await model.search.task?.value
        try #"{"cat": false}"#.write(to: workspace.folder.url.appending(path: "data.json"), atomically: true, encoding: .utf8)
        model.replace.replacement = "dog"
        model.prepareReplaceAll()
        await model.replace.task?.value
        let plan = try #require(model.replace.plan)
        #expect(plan.files.count == 2)
        #expect(plan.skipped.count == 1)
        model.replace.setIncluded(false, try #require(plan.files.last).id)

        // A sheet draws on the window background.
        let view = ReplacePreviewSheet(model: model).background(Color(nsColor: .windowBackgroundColor))
        let bitmap = try OffscreenRenderer.render(view, size: Self.size, appearance: appearance)
        try OffscreenRenderer.attach(bitmap, named: "replace-preview-\(appearance.rawValue).png")

        let content = OffscreenRenderer.contentPixels(in: bitmap, appearance: appearance)
        let blank = try OffscreenRenderer.blankContentPixels(size: Self.size, appearance: appearance)
        #expect(content > blank + 300, "files and changes should be visible (blank: \(blank), view: \(content))")
    }

    @Test func summaryCountsReplacementsAndFiles() {
        #expect(ReplacePreviewSheet.summary(replacements: 0, files: 0) == "Nothing to replace")
        #expect(ReplacePreviewSheet.summary(replacements: 1, files: 1) == "1 replacement in 1 file")
        #expect(ReplacePreviewSheet.summary(replacements: 12, files: 4) == "12 replacements in 4 files")
    }
}
