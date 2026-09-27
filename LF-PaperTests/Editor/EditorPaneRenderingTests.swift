//
//  EditorPaneRenderingTests.swift
//  LF-PaperTests
//

import AppKit
import SwiftUI
import Testing
@testable import LF_Paper

/// Renders the editor column offscreen in each of its states: nothing open, a JSON file,
/// a file deleted on disk with unsaved edits, and the scratchpad.
@MainActor
struct EditorPaneRenderingTests {
    private static let size = NSSize(width: 520, height: 200)

    private func expectVisible(
        _ model: WorkspaceModel,
        appearance: NSAppearance.Name = .darkAqua,
        named name: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let bitmap = try OffscreenRenderer.render(EditorPane(model: model), size: Self.size, appearance: appearance)
        try OffscreenRenderer.attach(bitmap, named: "editor-pane-\(name)-\(appearance.rawValue).png")
        let content = OffscreenRenderer.contentPixels(in: bitmap, appearance: appearance)
        let blank = try OffscreenRenderer.blankContentPixels(size: Self.size, appearance: appearance)
        #expect(content > blank + 30, "\(name) should be visible (blank: \(blank), pane: \(content))", sourceLocation: sourceLocation)
    }

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func showsAHintWhenNothingIsOpen(appearance: NSAppearance.Name) throws {
        let workspace = try TestWorkspace()

        try expectVisible(workspace.model, appearance: appearance, named: "empty")
    }

    @Test func showsTheJSONBarAboveAJSONFile() async throws {
        let workspace = try TestWorkspace(files: ["data.json": #"{"a": 1}"#])
        try await workspace.openJSON("data.json")

        try expectVisible(workspace.model, named: "json")
    }

    @Test func warnsWhenTheEditedFileWasDeleted() throws {
        let workspace = try TestWorkspace(files: ["a.md": "# A"])
        try workspace.open("a.md")
        workspace.model.updateDocumentText("# A edited")
        try FileManager.default.removeItem(at: workspace.folder.url.appending(path: "a.md"))
        workspace.model.reloadAll()
        #expect(workspace.model.isDocumentMissingOnDisk)

        try expectVisible(workspace.model, appearance: .aqua, named: "missing")
    }

    @Test func saysANewFileIsNotSavedYet() throws {
        let workspace = try TestWorkspace(files: ["data.json": #"[{"a": 1}]"#])
        try workspace.open("data.json")
        workspace.model.convertToYAML()
        #expect(workspace.model.document?.isNew == true)

        try expectVisible(workspace.model, appearance: .aqua, named: "new-file")
    }

    @Test func showsTheScratchpadBarAndText() throws {
        let workspace = try TestWorkspace()
        workspace.model.showScratchpad()
        workspace.model.updateScratchpadText("Explain this stack trace.")

        try expectVisible(workspace.model, named: "scratchpad")
    }
}
