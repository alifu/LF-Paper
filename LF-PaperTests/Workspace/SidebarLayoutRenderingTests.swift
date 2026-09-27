//
//  SidebarLayoutRenderingTests.swift
//  LF-PaperTests
//

import AppKit
import SwiftUI
import Testing
@testable import LF_Paper

/// The sidebar's mode picker stays at the top whatever the mode shows below it.
/// Regression: an empty outline ("No Outline", "No Headings") was centred, taking the picker with it.
@MainActor
struct SidebarLayoutRenderingTests {
    private static let size = NSSize(width: 260, height: 500)
    /// The picker has 6 pt of padding; anything much lower means the content was centred.
    private static let maximumTopInset = 20

    /// The first pixel row (from the top) that differs clearly from the background.
    private func firstContentRow(in bitmap: NSBitmapImageRep) throws -> Int {
        let background = try #require(bitmap.colorAt(x: 2, y: 2)?.usingColorSpace(.deviceRGB)?.brightnessComponent)
        for y in 0..<bitmap.pixelsHigh {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                guard let brightness = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)?.brightnessComponent else { continue }
                if abs(brightness - background) > 0.1 { return y }
            }
        }
        return bitmap.pixelsHigh
    }

    private func topOfContent(_ model: WorkspaceModel, named name: String) throws -> Int {
        let view = SidebarView(model: model)
            .environment(CompareModel())
            .background(Color(nsColor: .windowBackgroundColor))
        let bitmap = try OffscreenRenderer.render(view, size: Self.size, appearance: .aqua)
        try OffscreenRenderer.attach(bitmap, named: "sidebar-\(name).png")
        let scale = max(bitmap.pixelsHigh / Int(Self.size.height), 1)
        return try firstContentRow(in: bitmap) / scale
    }

    @Test func outlineWithoutAMarkdownFileKeepsThePickerAtTheTop() throws {
        let workspace = try TestWorkspace(files: ["data.json": "{}"])
        try workspace.open("data.json")
        workspace.model.sidebarMode = .outline

        #expect(try topOfContent(workspace.model, named: "outline-no-markdown") <= Self.maximumTopInset)
    }

    @Test func outlineWithoutHeadingsKeepsThePickerAtTheTop() async throws {
        let workspace = try TestWorkspace(files: ["notes.md": "Just text, no headings.\n"])
        try workspace.open("notes.md")
        let document = try #require(workspace.model.document)
        await workspace.model.outline.refresh(document.text, documentID: document.id)
        workspace.model.sidebarMode = .outline

        #expect(try topOfContent(workspace.model, named: "outline-no-headings") <= Self.maximumTopInset)
    }

    @Test(arguments: [SidebarMode.files, .search])
    func otherModesKeepThePickerAtTheTop(mode: SidebarMode) throws {
        let workspace = try TestWorkspace(files: ["notes.md": "# Notes\n"])
        workspace.model.sidebarMode = mode

        #expect(try topOfContent(workspace.model, named: "mode-\(mode)") <= Self.maximumTopInset)
    }
}
