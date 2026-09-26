//
//  JSONPanesRenderingTests.swift
//  LF-PaperTests
//

import AppKit
import SwiftUI
import Testing
@testable import LF_Paper

/// Renders the JSON editor bar and tree pane offscreen for valid and invalid JSON, in dark and light mode.
@MainActor
struct JSONPanesRenderingTests {
    private static let barSize = NSSize(width: 520, height: 32)
    private static let paneSize = NSSize(width: 320, height: 240)
    private static let valid = #"{"name": "Ada", "tags": ["math", "code"]}"#
    private static let invalid = #"{"name": "Ada",}"#

    private func expectVisible(
        _ view: some View,
        size: NSSize,
        appearance: NSAppearance.Name,
        named name: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let bitmap = try OffscreenRenderer.render(view, size: size, appearance: appearance)
        try OffscreenRenderer.attach(bitmap, named: "\(name)-\(appearance.rawValue).png")
        let content = OffscreenRenderer.contentPixels(in: bitmap, appearance: appearance)
        let blank = try OffscreenRenderer.blankContentPixels(size: size, appearance: appearance)
        #expect(content > blank + 30, "\(name) should show text (blank: \(blank), rendered: \(content))", sourceLocation: sourceLocation)
    }

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func barShowsValidity(appearance: NSAppearance.Name) async throws {
        let workspace = try TestWorkspace(files: ["valid.json": Self.valid, "invalid.json": Self.invalid])

        try await workspace.openJSON("valid.json")
        #expect(workspace.model.json.status == .valid)
        try expectVisible(JSONEditorBar(model: workspace.model), size: Self.barSize, appearance: appearance, named: "json-bar-valid")

        try await workspace.openJSON("invalid.json")
        try expectVisible(JSONEditorBar(model: workspace.model), size: Self.barSize, appearance: appearance, named: "json-bar-invalid")
    }

    @Test func barShowsCheckingBeforeTheFirstParse() throws {
        let workspace = try TestWorkspace(files: ["data.json": Self.valid])
        try workspace.open("data.json") // not awaited: still being checked

        try expectVisible(JSONEditorBar(model: workspace.model), size: Self.barSize, appearance: .darkAqua, named: "json-bar-checking")
    }

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func treePaneShowsTheTree(appearance: NSAppearance.Name) async throws {
        let workspace = try TestWorkspace(files: ["data.json": Self.valid])
        try await workspace.openJSON("data.json")

        try expectVisible(JSONTreePane(model: workspace.model), size: Self.paneSize, appearance: appearance, named: "json-tree")
    }

    @Test func treePaneExplainsInvalidJSON() async throws {
        let workspace = try TestWorkspace(files: ["data.json": Self.invalid])
        try await workspace.openJSON("data.json")
        #expect(workspace.model.json.tree == nil)

        try expectVisible(JSONTreePane(model: workspace.model), size: Self.paneSize, appearance: .darkAqua, named: "json-tree-invalid")
    }

    @Test func treePaneKeepsTheLastValidTreeWithABanner() async throws {
        let workspace = try TestWorkspace(files: ["data.json": Self.valid])
        try await workspace.openJSON("data.json")
        workspace.model.updateDocumentText(Self.invalid)
        await workspace.model.json.analysisTask?.value
        #expect(workspace.model.json.tree != nil)

        try expectVisible(JSONTreePane(model: workspace.model), size: Self.paneSize, appearance: .aqua, named: "json-tree-stale")
    }
}
