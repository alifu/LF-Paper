//
//  WorkspaceModelTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

@MainActor
final class WorkspaceModelTests {
    private let suiteName = "LFPaperTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let folder: TemporaryDirectory

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        folder = try TemporaryDirectory()
    }

    deinit {
        // deinit is nonisolated, so it can't touch the main-actor `defaults` property.
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    private func makeModel() -> WorkspaceModel {
        WorkspaceModel(
            fileService: LocalFileService(),
            bookmarkStore: BookmarkStore(defaults: defaults),
            watchesFileSystem: false
        )
    }

    private func openedModel() -> WorkspaceModel {
        let model = makeModel()
        model.openFolder(folder.url)
        return model
    }

    private func names(in model: WorkspaceModel, folder folderURL: URL? = nil) -> [String] {
        model.children(of: folderURL ?? folder.url).map(\.name)
    }

    private func item(named name: String, in model: WorkspaceModel, folder folderURL: URL? = nil) throws -> FileItem {
        try #require(model.children(of: folderURL ?? folder.url).first { $0.name == name })
    }

    // MARK: Opening

    @Test func openingFolderListsItsTopLevelItems() throws {
        try folder.makeFolder("docs")
        try folder.makeFile("notes.md")

        let model = openedModel()

        #expect(model.rootURL == folder.url)
        #expect(names(in: model) == ["docs", "notes.md"])
        #expect(model.presentedError == nil)
    }

    @Test func openingMissingFolderPresentsError() {
        let missing = folder.url.appending(path: "missing", directoryHint: .isDirectory)
        let model = makeModel()

        model.openFolder(missing)

        #expect(model.rootURL == nil)
        #expect(model.presentedError == .fileNotFound(missing))
    }

    @Test func restoreLastFolderReopensThePreviouslyOpenedFolder() throws {
        try folder.makeFile("notes.md")
        _ = openedModel()

        let relaunched = makeModel()
        relaunched.restoreLastFolder()

        let root = try #require(relaunched.rootURL)
        #expect(root.resolvingSymlinksInPath().path == folder.url.resolvingSymlinksInPath().path)
        #expect(relaunched.children(of: root).map(\.name) == ["notes.md"])
    }

    // MARK: Tree

    @Test func expandingFolderLoadsItsChildren() throws {
        try folder.makeFile("docs/guide.md")
        let model = openedModel()
        let docs = try item(named: "docs", in: model)

        model.setExpanded(docs.url, true)

        #expect(model.expandedFolders.contains(docs.url))
        #expect(names(in: model, folder: docs.url) == ["guide.md"])
    }

    @Test func collapsingFolderRemovesItFromExpandedFolders() throws {
        try folder.makeFolder("docs")
        let model = openedModel()
        let docs = try item(named: "docs", in: model)

        model.setExpanded(docs.url, true)
        model.setExpanded(docs.url, false)

        #expect(!model.expandedFolders.contains(docs.url))
    }

    @Test func reloadPicksUpExternalChanges() throws {
        let model = openedModel()
        try folder.makeFile("added-later.md")

        model.reloadAll()

        #expect(names(in: model) == ["added-later.md"])
    }

    @Test func showingHiddenFilesRevealsDotFiles() throws {
        try folder.makeFile(".hidden.md")
        let model = openedModel()
        #expect(names(in: model).isEmpty)

        model.showsHiddenFiles = true

        #expect(names(in: model) == [".hidden.md"])
    }

    // MARK: Selection and documents

    @Test func selectingFileOpensItsDocument() throws {
        try folder.makeFile("notes.md", contents: "# Notes")
        let model = openedModel()

        model.selection = try item(named: "notes.md", in: model).url

        #expect(model.document?.text == "# Notes")
        #expect(model.document?.isDirty == false)
    }

    @Test func selectingFolderKeepsTheOpenDocument() throws {
        try folder.makeFile("notes.md", contents: "# Notes")
        try folder.makeFolder("docs")
        let model = openedModel()
        model.selection = try item(named: "notes.md", in: model).url

        model.selection = try item(named: "docs", in: model).url

        #expect(model.document?.url.lastPathComponent == "notes.md")
    }

    @Test func saveWritesEditedTextAndClearsDirtyState() throws {
        try folder.makeFile("notes.md", contents: "old")
        let model = openedModel()
        model.selection = try item(named: "notes.md", in: model).url

        model.updateDocumentText("new")
        #expect(model.document?.isDirty == true)
        model.save()

        #expect(try folder.contents(of: "notes.md") == "new")
        #expect(model.document?.isDirty == false)
    }

    // MARK: Unsaved changes

    /// A workspace with "a.md" ("A") open and edited to "A edited", plus an untouched "b.md" ("B").
    private func modelWithUnsavedEdit() throws -> (model: WorkspaceModel, b: FileItem) {
        try folder.makeFile("a.md", contents: "A")
        try folder.makeFile("b.md", contents: "B")
        let model = openedModel()
        model.selection = try item(named: "a.md", in: model).url
        model.updateDocumentText("A edited")
        return (model, try item(named: "b.md", in: model))
    }

    @Test func switchingFilesWithUnsavedChangesAsksFirst() throws {
        let (model, b) = try modelWithUnsavedEdit()

        model.selection = b.url

        #expect(model.pendingAction == .openFile(b.url))
        #expect(model.document?.url.lastPathComponent == "a.md")
        #expect(model.hasUnsavedChanges)
    }

    @Test func savingBeforeSwitchingWritesTheEditsThenOpensTheNewFile() throws {
        let (model, b) = try modelWithUnsavedEdit()
        model.selection = b.url

        model.resolvePendingAction(.save)

        #expect(try folder.contents(of: "a.md") == "A edited")
        #expect(model.document?.text == "B")
        #expect(model.pendingAction == nil)
    }

    @Test func discardingBeforeSwitchingOpensTheNewFileWithoutWriting() throws {
        let (model, b) = try modelWithUnsavedEdit()
        model.selection = b.url

        model.resolvePendingAction(.discard)

        #expect(try folder.contents(of: "a.md") == "A")
        #expect(model.document?.text == "B")
    }

    @Test func cancellingSwitchKeepsTheEditsAndReselectsTheOpenFile() throws {
        let (model, b) = try modelWithUnsavedEdit()
        model.selection = b.url

        model.resolvePendingAction(.cancel)

        #expect(model.document?.text == "A edited")
        #expect(model.selection?.lastPathComponent == "a.md")
        #expect(model.pendingAction == nil)
    }

    @Test func openingAnotherFolderWithUnsavedChangesAsksFirst() throws {
        let (model, _) = try modelWithUnsavedEdit()
        let other = try TemporaryDirectory()

        model.openFolder(other.url)
        #expect(model.pendingAction == .openFolder(other.url))
        #expect(model.rootURL == folder.url)

        model.resolvePendingAction(.discard)
        #expect(model.rootURL == other.url)
        #expect(model.document == nil)
    }

    @Test func discardUnsavedChangesRevertsToTheSavedText() throws {
        let (model, _) = try modelWithUnsavedEdit()

        model.discardUnsavedChanges()

        #expect(model.document?.text == "A")
        #expect(!model.hasUnsavedChanges)
    }

    @Test func fileDeletedOnDiskKeepsUnsavedEditsUntilSavedAgain() throws {
        let (model, _) = try modelWithUnsavedEdit()
        try FileManager.default.removeItem(at: folder.url.appending(path: "a.md"))

        model.reloadAll()
        #expect(model.document?.text == "A edited")
        #expect(model.isDocumentMissingOnDisk)

        #expect(model.save())
        #expect(try folder.contents(of: "a.md") == "A edited")
        #expect(!model.isDocumentMissingOnDisk)
    }

    @Test func cleanDocumentReloadsWhenChangedOnDisk() throws {
        try folder.makeFile("a.md", contents: "A")
        let model = openedModel()
        model.selection = try item(named: "a.md", in: model).url
        try folder.makeFile("a.md", contents: "A changed elsewhere")

        model.reloadAll()

        #expect(model.document?.text == "A changed elsewhere")
        #expect(model.document?.isDirty == false)
    }

    @Test func editedDocumentKeepsItsEditsWhenChangedOnDisk() throws {
        let (model, _) = try modelWithUnsavedEdit()
        try folder.makeFile("a.md", contents: "A changed elsewhere")

        model.reloadAll()

        #expect(model.document?.text == "A edited")
    }

    // MARK: File operations

    @Test func createFileAddsUniqueUntitledFilesAndSelectsThem() throws {
        let model = openedModel()

        model.createFile(in: folder.url)
        model.createFile(in: folder.url)

        #expect(names(in: model) == ["Untitled 2.md", "Untitled.md"])
        #expect(model.selection?.lastPathComponent == "Untitled 2.md")
        #expect(model.document?.text == "")
    }

    @Test func createFolderInsideSubfolderExpandsIt() throws {
        try folder.makeFolder("docs")
        let model = openedModel()
        let docs = try item(named: "docs", in: model)

        model.createFolder(in: docs.url)

        #expect(model.expandedFolders.contains(docs.url))
        #expect(names(in: model, folder: docs.url) == ["New Folder"])
    }

    @Test func targetFolderForNewItemsIsTheFolderOrTheFilesParent() throws {
        try folder.makeFile("docs/guide.md")
        let model = openedModel()
        let docs = try item(named: "docs", in: model)
        model.setExpanded(docs.url, true)
        let guide = try item(named: "guide.md", in: model, folder: docs.url)

        #expect(model.targetFolder(for: docs) == docs.url)
        #expect(model.targetFolder(for: guide)?.lastPathComponent == "docs")
        #expect(model.targetFolder(for: nil) == folder.url)
    }

    @Test func renameKeepsTheRenamedFileSelectedAndOpen() throws {
        try folder.makeFile("old.md", contents: "text")
        let model = openedModel()
        let old = try item(named: "old.md", in: model)
        model.selection = old.url

        model.rename(old, to: "new.md")

        #expect(names(in: model) == ["new.md"])
        #expect(model.selection?.lastPathComponent == "new.md")
        #expect(model.document?.url.lastPathComponent == "new.md")
    }

    @Test func renameToExistingNamePresentsError() throws {
        try folder.makeFile("a.md")
        try folder.makeFile("b.md")
        let model = openedModel()

        model.rename(try item(named: "a.md", in: model), to: "b.md")

        #expect(model.presentedError == .alreadyExists(folder.url.appending(path: "b.md", directoryHint: .notDirectory)))
        #expect(names(in: model) == ["a.md", "b.md"])
    }

    @Test func moveToTrashRemovesItemAndClosesItsDocument() throws {
        try folder.makeFile("gone.md", contents: "bye")
        let model = openedModel()
        let gone = try item(named: "gone.md", in: model)
        model.selection = gone.url

        model.moveToTrash(gone)

        #expect(names(in: model).isEmpty)
        #expect(model.selection == nil)
        #expect(model.document == nil)
    }
}
