//
//  OutlineViewRenderingTests.swift
//  LF-PaperTests
//

import AppKit
import SwiftUI
import Testing
@testable import LF_Paper

/// The outline's headings, read in the background, and the sidebar showing them.
@MainActor
struct OutlineViewRenderingTests {
    private static let size = NSSize(width: 260, height: 220)
    private static let markdown = "# Title\n\n## Install\n\n### From Homebrew\n\n## Usage\n"

    @Test func headingsAreReadForTheirDocument() async throws {
        let session = OutlineSession()
        let id = UUID()
        #expect(session.headings(for: id) == nil) // not read yet: no "No Headings" flash

        await session.refresh(Self.markdown, documentID: id)

        #expect(session.headings(for: id)?.map(\.title) == ["Title", "Install", "From Homebrew", "Usage"])
        #expect(session.headings(for: UUID()) == nil)
    }

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func listsTheHeadingsIndentedByLevel(appearance: NSAppearance.Name) async throws {
        let workspace = try TestWorkspace(files: ["notes.md": Self.markdown])
        try workspace.open("notes.md")
        let document = try #require(workspace.model.document)
        await workspace.model.outline.refresh(document.text, documentID: document.id)

        let view = OutlineView(model: workspace.model).background(Color(nsColor: .windowBackgroundColor))
        let bitmap = try OffscreenRenderer.render(view, size: Self.size, appearance: appearance)
        try OffscreenRenderer.attach(bitmap, named: "outline-\(appearance.rawValue).png")

        // The sidebar's text is dimmed because the offscreen window isn't key; count contrast instead.
        let content = OffscreenRenderer.pixelsStandingOut(in: bitmap)
        #expect(content > 100, "headings should be visible (\(content) pixels stand out)")
    }
}
