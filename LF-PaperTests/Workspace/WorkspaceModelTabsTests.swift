//
//  WorkspaceModelTabsTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

/// Several open files as tabs: opening, switching, closing (with unsaved changes), Save All and autosave.
@MainActor
final class WorkspaceModelTabsTests {
    private let suiteName = "LFPaperTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let folder: TemporaryDirectory

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        folder = try TemporaryDirectory()
        try folder.makeFile("a.md", contents: "A")
        try folder.makeFile("b.md", contents: "B")
        try folder.makeFile("c.md", contents: "C")
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    private func openedModel() -> WorkspaceModel {
        let model = WorkspaceModel(
            fileService: LocalFileService(),
            bookmarkStore: BookmarkStore(defaults: defaults),
            recentFolders: RecentFolders(defaults: defaults),
            watchesFileSystem: false
        )
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

    private func tabNames(_ model: WorkspaceModel) -> [String] {
        model.tabs.map(\.url.lastPathComponent)
    }

    // MARK: Opening and switching

    @Test func selectingFilesOpensEachInItsOwnTab() throws {
        let model = openedModel()

        try open("a.md", "b.md", in: model)

        #expect(tabNames(model) == ["a.md", "b.md"])
        #expect(model.document?.text == "B")
    }

    @Test func selectingAnOpenFileSwitchesToItsTab() throws {
        let model = openedModel()
        try open("a.md", "b.md", "a.md", in: model)

        #expect(tabNames(model) == ["a.md", "b.md"])
        #expect(model.document?.text == "A")
    }

    @Test func newTabsOpenNextToTheActiveTab() throws {
        let model = openedModel()
        try open("a.md", "b.md", "a.md", "c.md", in: model)

        #expect(tabNames(model) == ["a.md", "c.md", "b.md"])
    }

    @Test func switchingFilesKeepsUnsavedEditsWithoutAsking() throws {
        let model = openedModel()
        try open("a.md", in: model)
        model.updateDocumentText("A edited")

        try open("b.md", in: model)

        #expect(model.pendingAction == nil)
        #expect(model.document?.text == "B")
        #expect(model.tabs.first?.text == "A edited")
        #expect(model.hasUnsavedChanges)
        #expect(!model.activeTabHasUnsavedChanges)
    }

    @Test func activatingATabSelectsItsFileInTheSidebar() throws {
        let model = openedModel()
        try open("a.md", "b.md", in: model)
        let first = try #require(model.tabs.first)

        model.activateTab(first.id)

        #expect(model.document?.id == first.id)
        #expect(model.selection?.lastPathComponent == "a.md")
    }

    @Test func nextAndPreviousTabWrapAround() throws {
        let model = openedModel()
        try open("a.md", "b.md", "c.md", in: model)

        model.activateNextTab()
        #expect(model.document?.text == "A")
        model.activatePreviousTab()
        #expect(model.document?.text == "C")
    }

    // MARK: Closing

    @Test func closingATabActivatesItsRightNeighbourOrElseItsLeft() throws {
        let model = openedModel()
        try open("a.md", "b.md", "c.md", in: model)
        try open("b.md", in: model)

        model.closeActiveTab()
        #expect(tabNames(model) == ["a.md", "c.md"])
        #expect(model.document?.text == "C")

        model.closeActiveTab()
        #expect(model.document?.text == "A")

        model.closeActiveTab()
        #expect(model.tabs.isEmpty)
        #expect(model.document == nil)
        #expect(model.selection == nil)
    }

    @Test func closingATabWithUnsavedChangesAsksFirst() throws {
        let model = openedModel()
        try open("a.md", in: model)
        model.updateDocumentText("A edited")
        let tab = try #require(model.document)

        model.closeTab(tab.id)

        #expect(model.pendingAction == .closeTab(tab.id))
        #expect(tabNames(model) == ["a.md"])
    }

    @Test(arguments: [
        (WorkspaceModel.UnsavedChangesDecision.save, "A edited", 0),
        (.discard, "A", 0),
        (.cancel, "A", 1),
    ])
    func resolvingACloseTabPrompt(decision: WorkspaceModel.UnsavedChangesDecision, onDisk: String, remainingTabs: Int) throws {
        let model = openedModel()
        try open("a.md", in: model)
        model.updateDocumentText("A edited")
        model.closeTab(try #require(model.document).id)

        model.resolvePendingAction(decision)

        #expect(try folder.contents(of: "a.md") == onDisk)
        #expect(model.tabs.count == remainingTabs)
        #expect(model.pendingAction == nil)
    }

    @Test func openingAnotherFolderClosesAllTabs() throws {
        let model = openedModel()
        try open("a.md", "b.md", in: model)
        let other = try TemporaryDirectory()

        model.openFolder(other.url)

        #expect(model.tabs.isEmpty)
        #expect(model.document == nil)
    }

    // MARK: Saving

    @Test func saveWritesOnlyTheActiveTab() throws {
        let model = openedModel()
        try open("a.md", in: model)
        model.updateDocumentText("A edited")
        try open("b.md", in: model)
        model.updateDocumentText("B edited")

        #expect(model.save())

        #expect(try folder.contents(of: "a.md") == "A")
        #expect(try folder.contents(of: "b.md") == "B edited")
    }

    @Test func saveAllWritesEveryEditedTab() throws {
        let model = openedModel()
        try open("a.md", in: model)
        model.updateDocumentText("A edited")
        try open("b.md", in: model)
        model.updateDocumentText("B edited")

        #expect(model.saveAll())

        #expect(try folder.contents(of: "a.md") == "A edited")
        #expect(try folder.contents(of: "b.md") == "B edited")
        #expect(!model.hasUnsavedChanges)
    }

    @Test func discardUnsavedChangesRevertsEveryTab() throws {
        let model = openedModel()
        try open("a.md", in: model)
        model.updateDocumentText("A edited")
        try open("b.md", in: model)
        model.updateDocumentText("B edited")

        model.discardUnsavedChanges()

        #expect(model.tabs.map(\.text) == ["A", "B"])
        #expect(!model.hasUnsavedChanges)
    }

    @Test func openingAnotherFolderAsksWhenAnyTabHasUnsavedChanges() throws {
        let model = openedModel()
        try open("a.md", in: model)
        model.updateDocumentText("A edited")
        try open("b.md", in: model)
        let other = try TemporaryDirectory()

        model.openFolder(other.url)
        #expect(model.pendingAction == .openFolder(other.url))

        model.resolvePendingAction(.save)
        #expect(try folder.contents(of: "a.md") == "A edited")
        #expect(model.rootURL == other.url)
    }

    // MARK: Disk changes

    @Test func aCleanTabWhoseFileIsDeletedCloses() throws {
        let model = openedModel()
        try open("a.md", "b.md", in: model)
        try FileManager.default.removeItem(at: try url("a.md", in: model))

        model.reloadAll()

        #expect(tabNames(model) == ["b.md"])
    }

    @Test func textOfAnyOpenTabIncludesItsUnsavedEdits() throws {
        let model = openedModel()
        try open("a.md", in: model)
        model.updateDocumentText("A edited")
        try open("b.md", in: model)

        let a = try #require(model.children(of: folder.url).first { $0.name == "a.md" })
        #expect(model.text(of: a) == "A edited")
    }

    // MARK: Autosave

    @Test func autosaveWritesEditsAfterAPause() async throws {
        let model = openedModel()
        model.autosaveDelay = .milliseconds(10)
        try open("a.md", in: model)

        model.updateDocumentText("A edited")
        await model.autosaveTask?.value

        #expect(try folder.contents(of: "a.md") == "A edited")
        #expect(!model.hasUnsavedChanges)
    }

    @Test func autosaveIsOffByDefault() async throws {
        let model = openedModel()
        try open("a.md", in: model)

        model.updateDocumentText("A edited")

        #expect(model.autosaveTask == nil)
        #expect(model.hasUnsavedChanges)
    }

    @Test func autosaveWaitsForTypingToStop() async throws {
        let model = openedModel()
        model.autosaveDelay = .milliseconds(50)
        try open("a.md", in: model)

        model.updateDocumentText("A1")
        let first = try #require(model.autosaveTask)
        model.updateDocumentText("A12")
        #expect(first.isCancelled) // typing again restarts the pause

        await model.autosaveTask?.value
        #expect(try folder.contents(of: "a.md") == "A12")
    }
}
