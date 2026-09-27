//
//  SwiftModelSheetRenderingTests.swift
//  LF-PaperTests
//

import AppKit
import SwiftUI
import Testing
@testable import LF_Paper

/// Renders the Generate Swift Model sheet offscreen, in dark and light mode.
@MainActor
struct SwiftModelSheetRenderingTests {
    private static let size = NSSize(width: 900, height: 560)

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func showsTheOptionsAndThePreview(appearance: NSAppearance.Name) async throws {
        let workspace = try TestWorkspace(files: [
            "users.json": #"[{"id": 1, "first_name": "Ada", "joined": "2026-09-27T10:15:00Z", "tags": []}]"#,
        ])
        try await workspace.openJSON("users.json")
        workspace.model.showSwiftModelGenerator()
        let session = try #require(workspace.model.swiftModelGenerator)
        session.options.conformances = [.hashable, .sendable]

        let view = SwiftModelSheet(model: workspace.model, session: session)
            .background(Color(nsColor: .windowBackgroundColor)) // a sheet draws on the window background
        let bitmap = try OffscreenRenderer.render(view, size: Self.size, appearance: appearance)
        try OffscreenRenderer.attach(bitmap, named: "swift-model-sheet-\(appearance.rawValue).png")

        let content = OffscreenRenderer.contentPixels(in: bitmap, appearance: appearance)
        let blank = try OffscreenRenderer.blankContentPixels(size: Self.size, appearance: appearance)
        #expect(content > blank + 500, "options and code should be visible (blank: \(blank), view: \(content))")
    }

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func explainsJSONThatCantBeModelled(appearance: NSAppearance.Name) async throws {
        let workspace = try TestWorkspace(files: ["number.json": "42"])
        try await workspace.openJSON("number.json")
        workspace.model.showSwiftModelGenerator()
        let session = try #require(workspace.model.swiftModelGenerator)

        let view = SwiftModelSheet(model: workspace.model, session: session)
            .background(Color(nsColor: .windowBackgroundColor))
        let bitmap = try OffscreenRenderer.render(view, size: Self.size, appearance: appearance)
        try OffscreenRenderer.attach(bitmap, named: "swift-model-sheet-error-\(appearance.rawValue).png")

        let content = OffscreenRenderer.contentPixels(in: bitmap, appearance: appearance)
        let blank = try OffscreenRenderer.blankContentPixels(size: Self.size, appearance: appearance)
        #expect(content > blank + 300, "the explanation should be visible (blank: \(blank), view: \(content))")
    }
}
