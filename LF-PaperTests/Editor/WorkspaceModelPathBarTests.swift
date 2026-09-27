//
//  WorkspaceModelPathBarTests.swift
//  LF-PaperTests
//

import AppKit
import Testing
@testable import LF_Paper

/// The path bar's actions: showing a part of the path in the sidebar, copying paths, revealing in Finder.
@MainActor
struct WorkspaceModelPathBarTests {
    private let workspace: TestWorkspace

    init() throws {
        workspace = try TestWorkspace(files: [
            "README.md": "# Readme",
            "docs/guide/setup.md": "Setup",
            "data.json": "{}",
        ])
    }

    private var model: WorkspaceModel { workspace.model }

    private func openSetup() async throws {
        await model.indexTask?.value
        model.open(try #require(model.fileIndex.first { $0.relativePath == "docs/guide/setup.md" }))
    }

    @Test func showsThePathOfTheOpenFile() async throws {
        #expect(model.pathSegments.isEmpty)
        try await openSetup()

        #expect(model.pathSegments.map(\.name) == [workspace.folder.url.lastPathComponent, "docs", "guide", "setup.md"])
    }

    @Test func theScratchpadHasNoPath() async throws {
        try await openSetup()

        model.showScratchpad()

        #expect(model.pathSegments.isEmpty)
    }

    @Test func aNewFileShowsWhereItWillBeSaved() async throws {
        try await workspace.openJSON("data.json")

        model.convertToYAML()

        #expect(model.pathSegments.last?.name == "data.yaml")
    }

    @Test func showingAFolderSelectsItInTheFilesSidebar() async throws {
        try await openSetup()
        model.sidebarMode = .search
        model.setExpanded(try #require(model.item(at: workspace.folder.url.appending(path: "docs")))
            .url, false)
        let guide = try #require(model.pathSegments.first { $0.name == "guide" })

        model.showInSidebar(guide.url)

        #expect(model.sidebarMode == .files)
        #expect(model.expandedFolders.map(\.lastPathComponent).contains("docs"))
        #expect(model.selection?.lastPathComponent == "guide")
        #expect(model.document?.url.lastPathComponent == "setup.md") // the tab stays
        #expect(model.sidebarRevealRequest != nil)
    }

    @Test func showingTheFileSelectsIt() async throws {
        try await openSetup()
        let folder = try #require(model.pathSegments.first { $0.name == "guide" })
        model.showInSidebar(folder.url)

        model.showInSidebar(try #require(model.pathSegments.last).url)

        #expect(model.selection?.lastPathComponent == "setup.md")
    }

    @Test func showingTheOpenFolderOnlySwitchesToFiles() async throws {
        try await openSetup()
        model.sidebarMode = .outline

        model.showInSidebar(try #require(model.pathSegments.first).url)

        #expect(model.sidebarMode == .files)
    }

    @Test func copiesTheFullOrRelativePath() async throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("LFPaperTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        try await openSetup()
        let file = try #require(model.pathSegments.last).url

        model.copyPath(of: file, relative: false, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == file.path(percentEncoded: false))

        model.copyPath(of: file, relative: true, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "docs/guide/setup.md")
    }

    @Test func revealsTheFileOrItsFolderWhenItIsntSaved() async throws {
        try await workspace.openJSON("data.json")
        let saved = try #require(model.document).url
        #expect(model.finderTarget(for: saved) == saved)

        model.convertToYAML()
        let unsaved = try #require(model.document).url

        #expect(model.finderTarget(for: unsaved) == unsaved.deletingLastPathComponent())
    }
}
