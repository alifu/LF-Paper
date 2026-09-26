//
//  WorkspaceModelFolderSearchTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

/// Search in Folder from the workspace: running, cancelling and opening a result.
@MainActor
struct WorkspaceModelFolderSearchTests {
    private let workspace: TestWorkspace

    init() throws {
        workspace = try TestWorkspace(files: [
            "README.md": "# Readme\nThe needle is here.",
            "docs/notes.md": "no match",
            "data/config.json": #"{"needle": true}"#,
            ".hidden/secret.md": "needle",
        ])
    }

    private var model: WorkspaceModel { workspace.model }

    private func search(_ text: String, options: SearchOptions = SearchOptions()) async {
        model.search.text = text
        model.search.options = options
        model.runFolderSearch()
        await model.search.task?.value
    }

    @Test func showingSearchSwitchesTheSidebarAndAsksForFocus() {
        model.showFolderSearch()

        #expect(model.sidebarMode == .search)
        #expect(model.searchFocusRequest != nil)
    }

    @Test func findsMatchesInEveryIndexedFile() async {
        await search("needle")

        #expect(model.search.results.map(\.file.relativePath) == ["data/config.json", "README.md"])
        #expect(model.search.matchCount == 2)
        #expect(!model.search.isSearching)
        #expect(model.search.searchedText == "needle")
    }

    @Test func searchesHiddenFilesOnlyWhenTheyAreShown() async {
        model.showsHiddenFiles = true

        await search("needle")

        #expect(model.search.results.map(\.file.relativePath).contains(".hidden/secret.md"))
    }

    @Test func searchesUnsavedEditsOfOpenFiles() async throws {
        await model.indexTask?.value
        model.open(try #require(model.fileIndex.first { $0.name == "notes.md" }))
        model.updateDocumentText("now with a needle")

        await search("needle")

        #expect(model.search.results.map(\.file.name).contains("notes.md"))
    }

    @Test func anInvalidPatternShowsAnErrorInsteadOfResults() async {
        await search("(", options: SearchOptions(usesRegularExpression: true))

        #expect(model.search.error != nil)
        #expect(model.search.results.isEmpty)
    }

    @Test func cancellingStopsTheSearch() async {
        model.search.text = "needle"
        model.runFolderSearch()

        model.search.cancel()
        await model.search.task?.value

        #expect(!model.search.isSearching)
    }

    @Test func openingAMatchOpensTheFileAndSelectsTheMatch() async throws {
        await search("needle")
        let readme = try #require(model.search.results.first { $0.file.name == "README.md" })

        model.open(readme.matches[0], in: readme)

        #expect(model.document?.url.lastPathComponent == "README.md")
        #expect(model.revealRequest?.range == readme.matches[0].range)
        #expect(model.revealRequest?.focusesEditor == true)
    }

    @Test func openingAnotherFolderClearsTheResults() async throws {
        await search("needle")
        let other = try TemporaryDirectory()

        model.openFolder(other.url)

        #expect(model.search.results.isEmpty)
        #expect(model.search.searchedText == nil)
    }
}
