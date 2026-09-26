//
//  QuickOpenPanelRenderingTests.swift
//  LF-PaperTests
//

import AppKit
import SwiftUI
import Testing
@testable import LF_Paper

/// Renders the Quick Open panel offscreen with results, in dark and light mode.
@MainActor
struct QuickOpenPanelRenderingTests {
    private static let size = NSSize(width: QuickOpenPanel.width + 40, height: 260)

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func listsTheFolderFiles(appearance: NSAppearance.Name) async throws {
        let workspace = try TestWorkspace(files: ["README.md": "", "docs/guide/setup.md": "", "data/config.json": "{}"])
        await workspace.model.indexTask?.value
        #expect(workspace.model.fileIndex.count == 3)

        let bitmap = try OffscreenRenderer.render(QuickOpenPanel(model: workspace.model).padding(20), size: Self.size, appearance: appearance)
        try OffscreenRenderer.attach(bitmap, named: "quick-open-\(appearance.rawValue).png")

        let content = OffscreenRenderer.contentPixels(in: bitmap, appearance: appearance)
        let blank = try OffscreenRenderer.blankContentPixels(size: Self.size, appearance: appearance)
        #expect(content > blank + 150, "rows should be visible (blank: \(blank), panel: \(content))")
    }
}
