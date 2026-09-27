//
//  WorkspaceModelReplaceTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

/// Replace All from the workspace: the preview, then writing closed files and editing open tabs, and Undo.
@MainActor
struct WorkspaceModelReplaceTests {
    private let workspace: TestWorkspace

    init() throws {
        workspace = try TestWorkspace(files: [
            "a.md": "cat and cat",
            "b.md": "one cat",
            "docs/c.md": "no match",
            "data.json": #"{"cat": 1}"#,
        ])
    }

    private var model: WorkspaceModel { workspace.model }

    private func url(_ path: String) -> URL {
        workspace.folder.url.appending(path: path, directoryHint: .notDirectory)
    }

    private func disk(_ path: String) throws -> String {
        try String(contentsOf: url(path), encoding: .utf8)
    }

    private func search(_ text: String, options: SearchOptions = SearchOptions()) async {
        model.search.text = text
        model.search.options = options
        model.runFolderSearch()
        await model.search.task?.value
    }

    /// Searches, then opens the preview of replacing with `replacement`.
    private func preview(_ find: String, with replacement: String, options: SearchOptions = SearchOptions()) async {
        await search(find, options: options)
        model.replace.replacement = replacement
        model.prepareReplaceAll()
        await model.replace.task?.value
    }

    private func replaceAll() async {
        model.applyReplaceAll()
        await model.search.task?.value // the search runs again
    }

    // MARK: Preview

    @Test func previewListsEveryFileWithItsChanges() async throws {
        await preview("cat", with: "dog")

        let plan = try #require(model.replace.plan)
        #expect(plan.files.map(\.file.relativePath).sorted() == ["a.md", "b.md", "data.json"])
        #expect(plan.replacementCount(excluding: []) == 4)
        #expect(model.replace.error == nil)
        #expect(!model.replace.isPreparing)
        #expect(try disk("a.md") == "cat and cat") // nothing written yet
    }

    @Test func replaceAllNeedsResults() async {
        #expect(!model.canReplaceAll)
        await search("zebra")
        #expect(!model.canReplaceAll)
        await search("cat")
        #expect(model.canReplaceAll)
    }

    @Test func usesTheQueryThatWasSearchedNotTheEditedField() async throws {
        await search("cat")
        model.search.text = "and" // typed but not searched yet
        model.replace.replacement = "dog"
        model.prepareReplaceAll()
        await model.replace.task?.value

        #expect(model.replace.plan?.replacementCount(excluding: []) == 4)
    }

    @Test func anInvalidTemplateIsExplainedWithoutAPreview() async {
        await preview("(cat)", with: "$2", options: SearchOptions(usesRegularExpression: true))

        #expect(model.replace.plan == nil)
        #expect(model.replace.error == .noSuchGroup(2, available: 1))
    }

    @Test func cancellingThePreviewWritesNothing() async throws {
        await preview("cat", with: "dog")

        model.replace.cancel()

        #expect(model.replace.plan == nil)
        #expect(try disk("a.md") == "cat and cat")
    }

    // MARK: Applying

    @Test func closedFilesAreWrittenToDisk() async throws {
        await preview("cat", with: "dog")

        await replaceAll()

        #expect(try disk("a.md") == "dog and dog")
        #expect(try disk("b.md") == "one dog")
        #expect(model.replace.plan == nil)
        #expect(model.replace.outcome?.message == "Replaced 4 matches in 3 files.")
        #expect(model.replace.outcome?.skipped.isEmpty == true)
    }

    @Test func openTabsAreEditedAndLeftUnsaved() async throws {
        try workspace.open("a.md")
        try workspace.open("b.md") // a.md is now a background tab
        await preview("cat", with: "dog")

        await replaceAll()

        let a = try #require(model.tabs.first { $0.url.lastPathComponent == "a.md" })
        #expect(a.text == "dog and dog")
        #expect(model.hasUnsavedChanges(inTab: a.id))
        #expect(model.document?.text == "one dog")
        #expect(model.activeTabHasUnsavedChanges)
        #expect(try disk("a.md") == "cat and cat") // saved as usual, by the user
        #expect(try disk("data.json") == #"{"dog": 1}"#) // closed: written
    }

    @Test func leftOutFilesAreNotChanged() async throws {
        await preview("cat", with: "dog")

        model.replace.setIncluded(false, url("a.md"))
        #expect(!model.replace.isIncluded(url("a.md")))
        await replaceAll()

        #expect(try disk("a.md") == "cat and cat")
        #expect(try disk("b.md") == "one dog")
        #expect(model.replace.outcome?.message == "Replaced 2 matches in 2 files.")
    }

    @Test func afterwardsTheSearchShowsWhatsLeft() async throws {
        await preview("cat", with: "dog")
        model.replace.setIncluded(false, url("a.md"))

        await replaceAll()

        #expect(model.search.results.map(\.file.relativePath) == ["a.md"])
    }

    @Test func filesChangedSinceTheSearchAreSkippedAndListed() async throws {
        await preview("cat", with: "dog")
        try "cat, edited elsewhere".write(to: url("a.md"), atomically: true, encoding: .utf8)

        await replaceAll()

        #expect(try disk("a.md") == "cat, edited elsewhere")
        #expect(try disk("b.md") == "one dog")
        let skipped = try #require(model.replace.outcome?.skipped.first)
        #expect(skipped.file.relativePath == "a.md")
        #expect(skipped.reason == .changedSinceSearch)
    }

    @Test func tabsEditedSinceThePreviewAreSkipped() async throws {
        try workspace.open("b.md")
        await preview("cat", with: "dog")
        model.updateDocumentText("one cat, typed")

        await replaceAll()

        #expect(model.document?.text == "one cat, typed")
        #expect(model.replace.outcome?.skipped.map(\.reason) == [.changedSinceSearch])
    }

    @Test func aWriteFailureIsReportedWhileTheOthersGoThrough() async throws {
        try workspace.folder.makeFile("locked/d.md", contents: "cat")
        let locked = workspace.folder.url.appending(path: "locked", directoryHint: .isDirectory)
        model.refreshFileIndex()
        await model.indexTask?.value
        await preview("cat", with: "dog")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        await replaceAll()

        #expect(try disk("locked/d.md") == "cat")
        #expect(try disk("a.md") == "dog and dog")
        let skipped = try #require(model.replace.outcome?.skipped.first)
        #expect(skipped.file.relativePath == "locked/d.md")
        if case .writeFailed = skipped.reason {} else { Issue.record("expected a write failure, got \(skipped.reason)") }
        #expect(model.replace.outcome?.message.hasPrefix("Replaced 4 matches in 3 files.") == true)
    }

    // MARK: Undo

    @Test func undoPutsBackTheWrittenFiles() async throws {
        try workspace.open("b.md")
        await preview("cat", with: "dog")
        await replaceAll()
        #expect(model.replace.canUndo)

        model.undoReplaceAll()
        await model.search.task?.value

        #expect(try disk("a.md") == "cat and cat")
        #expect(try disk("data.json") == #"{"cat": 1}"#)
        #expect(model.document?.text == "one dog") // tabs undo with their own ⌘Z
        #expect(!model.replace.canUndo)
        #expect(model.replace.outcome?.message == "Put back the original text of 2 files.")
    }

    @Test func undoLeavesFilesChangedAfterTheReplaceAlone() async throws {
        await preview("cat", with: "dog")
        await replaceAll()
        try "dog, edited again".write(to: url("a.md"), atomically: true, encoding: .utf8)

        model.undoReplaceAll()

        #expect(try disk("a.md") == "dog, edited again")
        #expect(try disk("b.md") == "one cat")
        #expect(model.replace.outcome?.skipped.map(\.file.relativePath) == ["a.md"])
    }

    @Test func undoSkipsFilesOpenedAndEditedSince() async throws {
        await preview("cat", with: "dog")
        await replaceAll()
        try workspace.open("a.md")
        model.updateDocumentText("dog and dog, typed")

        model.undoReplaceAll()

        #expect(try disk("a.md") == "dog and dog")
        #expect(model.document?.text == "dog and dog, typed")
        #expect(model.replace.outcome?.skipped.map(\.file.relativePath) == ["a.md"])
    }

    @Test func undoUpdatesAnUneditedOpenTab() async throws {
        await preview("cat", with: "dog")
        await replaceAll()
        try workspace.open("a.md")

        model.undoReplaceAll()

        #expect(model.document?.text == "cat and cat")
        #expect(!model.activeTabHasUnsavedChanges)
    }

    @Test func openingAnotherFolderForgetsReplaceState() async throws {
        await preview("cat", with: "dog")
        await replaceAll()
        let other = try TemporaryDirectory()

        model.openFolder(other.url)

        #expect(!model.replace.canUndo)
        #expect(model.replace.outcome == nil)
    }
}
