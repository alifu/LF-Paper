//
//  PathBarRenderingTests.swift
//  LF-PaperTests
//

import AppKit
import SwiftUI
import Testing
@testable import LF_Paper

/// Renders the path bar offscreen, in dark and light mode, with a short path and a long one that doesn't fit.
@MainActor
struct PathBarRenderingTests {
    private static let height: CGFloat = 28

    private func render(
        _ relativePath: String,
        width: CGFloat,
        appearance: NSAppearance.Name,
        named name: String
    ) async throws -> NSBitmapImageRep {
        let workspace = try TestWorkspace(files: [relativePath: "text"])
        await workspace.model.indexTask?.value
        workspace.model.open(try #require(workspace.model.fileIndex.first { $0.relativePath == relativePath }))
        #expect(!workspace.model.pathSegments.isEmpty)

        // The editor column draws on the window background.
        let view = PathBar(model: workspace.model).background(Color(nsColor: .windowBackgroundColor))
        let bitmap = try OffscreenRenderer.render(view, size: NSSize(width: width, height: Self.height), appearance: appearance)
        try OffscreenRenderer.attach(bitmap, named: "path-bar-\(name)-\(appearance.rawValue).png")
        return bitmap
    }

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func showsEachPartOfAShortPath(appearance: NSAppearance.Name) async throws {
        let bitmap = try await render("docs/guide/setup.md", width: 520, appearance: appearance, named: "short")

        let content = OffscreenRenderer.contentPixels(in: bitmap, appearance: appearance)
        let blank = try OffscreenRenderer.blankContentPixels(size: NSSize(width: 520, height: Self.height), appearance: appearance)
        #expect(content > blank + 150, "the path should be visible (blank: \(blank), bar: \(content))")
    }

    /// Too long for the width: it still fits on one line, and the file name is still drawn at the end.
    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func shortensALongPathFromTheFront(appearance: NSAppearance.Name) async throws {
        let path = "a-rather-long-folder-name/another-long-folder/and-one-more-level/deeply/nested/notes-file.md"
        let bitmap = try await render(path, width: 300, appearance: appearance, named: "long")

        let content = OffscreenRenderer.contentPixels(in: bitmap, appearance: appearance)
        let blank = try OffscreenRenderer.blankContentPixels(size: NSSize(width: 300, height: Self.height), appearance: appearance)
        #expect(content > blank + 100, "the shortened path should be visible (blank: \(blank), bar: \(content))")
    }
}
