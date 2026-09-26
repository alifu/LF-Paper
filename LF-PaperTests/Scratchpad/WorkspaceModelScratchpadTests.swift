//
//  WorkspaceModelScratchpadTests.swift
//  LF-PaperTests
//

import AppKit
import Testing
@testable import LF_Paper

/// The scratchpad: a throwaway editor tab that is never saved and ignores the folder and its files.
@MainActor
final class WorkspaceModelScratchpadTests {
    private let suiteName = "LFPaperTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let folder: TemporaryDirectory

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        folder = try TemporaryDirectory()
        try folder.makeFile("a.md", contents: "A")
        try folder.makeFile("b.md", contents: "B")
        try folder.makeFile("data.json", contents: "{\"a\": 1}")
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    private func makeModel() -> WorkspaceModel {
        WorkspaceModel(
            fileService: LocalFileService(),
            bookmarkStore: BookmarkStore(defaults: defaults),
            recentFolders: RecentFolders(defaults: defaults),
            watchesFileSystem: false
        )
    }

    private func openedModel() -> WorkspaceModel {
        let model = makeModel()
        model.openFolder(folder.url)
        return model
    }

    private func url(_ name: String, in model: WorkspaceModel) throws -> URL {
        try #require(model.children(of: folder.url).first { $0.name == name }).url
    }

    private func open(_ names: String..., in model: WorkspaceModel) throws {
        for name in names {
            model.selection = try url(name, in: model)
        }
    }

    // MARK: Showing and leaving

    @Test func startsEmptyAndHidden() {
        let model = makeModel()

        #expect(!model.isScratchpadActive)
        #expect(model.scratchpadText.isEmpty)
    }

    @Test func showingItHidesTheFileWithoutClosingItsTab() throws {
        let model = openedModel()
        try open("a.md", "b.md", in: model)

        model.showScratchpad()

        #expect(model.isScratchpadActive)
        #expect(model.document == nil)
        #expect(model.tabs.map(\.url.lastPathComponent) == ["a.md", "b.md"])
        #expect(model.selection == nil) // nothing in the sidebar is showing
    }

    @Test func activatingATabLeavesIt() throws {
        let model = openedModel()
        try open("a.md", "b.md", in: model)
        model.showScratchpad()

        model.activateTab(model.tabs[0].id)

        #expect(!model.isScratchpadActive)
        #expect(model.document?.text == "A")
    }

    @Test func openingAFileFromTheSidebarLeavesIt() throws {
        let model = openedModel()
        try open("a.md", in: model)
        model.showScratchpad()

        try open("a.md", in: model) // the file that was already active

        #expect(!model.isScratchpadActive)
        #expect(model.document?.text == "A")
    }

    @Test func selectingAFolderKeepsItShowing() throws {
        let subfolder = try folder.makeFolder("notes")
        let model = openedModel()
        model.showScratchpad()

        model.selection = model.item(at: subfolder)?.url

        #expect(model.isScratchpadActive)
    }

    @Test func toggleGoesBackToTheLastFileTab() throws {
        let model = openedModel()
        try open("a.md", "b.md", in: model)

        model.toggleScratchpad()
        #expect(model.isScratchpadActive)

        model.toggleScratchpad()
        #expect(!model.isScratchpadActive)
        #expect(model.document?.text == "B")
        #expect(model.selection == (try url("b.md", in: model)))
    }

    @Test func toggleStaysWhenNoFileIsOpen() {
        let model = openedModel()

        model.toggleScratchpad()
        model.toggleScratchpad()

        #expect(model.isScratchpadActive)
    }

    @Test func closingTheLastTabBehindItKeepsItShowing() throws {
        let model = openedModel()
        try open("a.md", in: model)
        model.showScratchpad()

        model.closeTab(model.tabs[0].id)

        #expect(model.isScratchpadActive)
        #expect(model.tabs.isEmpty)
    }

    // MARK: Text

    @Test func editingChangesOnlyTheScratchpad() throws {
        let model = openedModel()
        try open("a.md", in: model)
        model.showScratchpad()

        model.updateScratchpadText("a prompt")

        #expect(model.scratchpadText == "a prompt")
        #expect(model.tabs[0].text == "A")
        #expect(!model.hasUnsavedChanges)
    }

    @Test func clearEmptiesIt() {
        let model = makeModel()
        model.updateScratchpadText("draft")

        model.clearScratchpad()

        #expect(model.scratchpadText.isEmpty)
    }

    @Test func textSurvivesOpeningAnotherFolderAndReloading() throws {
        let other = try TemporaryDirectory()
        let model = openedModel()
        model.updateScratchpadText("keep me")

        model.reloadAll()
        model.openFolder(other.url)

        #expect(model.scratchpadText == "keep me")
    }

    @Test func textSurvivesSwitchingTabs() throws {
        let model = openedModel()
        try open("a.md", in: model)
        model.showScratchpad()
        model.updateScratchpadText("keep me")

        model.activateTab(model.tabs[0].id)
        model.showScratchpad()

        #expect(model.scratchpadText == "keep me")
    }

    @Test func copyPutsTheWholeTextOnThePasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("LFPaperTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let model = makeModel()
        model.updateScratchpadText("line one\nline two")

        model.copyScratchpad(to: pasteboard)

        #expect(pasteboard.string(forType: .string) == "line one\nline two")
        #expect(model.scratchpadCopyID != nil)
    }

    // MARK: Never saved

    @Test func neverCountsAsUnsavedOrGetsWritten() throws {
        let model = openedModel()
        try open("a.md", in: model)
        model.showScratchpad()
        model.updateScratchpadText("not a file")

        #expect(!model.hasUnsavedChanges)
        #expect(model.unsavedDocuments.isEmpty)
        #expect(!model.activeTabHasUnsavedChanges)
        #expect(model.save())
        #expect(model.saveAll())
        #expect(try folder.contents(of: "a.md") == "A")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path(percentEncoded: false)).sorted() == ["a.md", "b.md", "data.json"])
    }

    @Test func autosaveIgnoresIt() throws {
        let model = openedModel()
        model.autosaveDelay = .milliseconds(10)
        model.showScratchpad()

        model.updateScratchpadText("not a file")

        #expect(model.autosaveTask == nil)
    }

    @Test func savingWhileShowingItStillSavesEditedFileTabs() throws {
        let model = openedModel()
        try open("a.md", in: model)
        model.updateDocumentText("A edited")
        model.showScratchpad()

        #expect(model.hasUnsavedChanges)
        #expect(model.saveAll())
        #expect(try folder.contents(of: "a.md") == "A edited")
    }

    // MARK: JSON

    @Test func jsonSessionIsInactiveWhileShowing() async throws {
        let model = openedModel()
        try open("data.json", in: model)
        await model.json.analysisTask?.value
        #expect(model.json.status == .valid)

        model.showScratchpad()
        #expect(model.json.status == .inactive)
        #expect(!model.isJSONDocument)

        model.toggleScratchpad()
        await model.json.analysisTask?.value
        #expect(model.json.status == .valid)
    }
}
