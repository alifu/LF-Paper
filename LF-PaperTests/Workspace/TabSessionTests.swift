//
//  TabSessionTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

/// Each folder's open tabs are remembered and reopened with it; the scratchpad never is.
@MainActor
final class TabSessionTests {
    private let suiteName = "LFPaperTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let folder: TemporaryDirectory

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        folder = try TemporaryDirectory()
        try folder.makeFile("a.md", contents: "Alpha text")
        try folder.makeFile("b.json", contents: "{}")
        try folder.makeFile("docs/c.md", contents: "Charlie")
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    /// A new window (or a relaunch): a fresh model sharing the stored settings.
    private func makeModel() -> WorkspaceModel {
        WorkspaceModel(
            bookmarkStore: BookmarkStore(defaults: defaults),
            recentFolders: RecentFolders(defaults: defaults),
            watchesFileSystem: false
        )
    }

    private func openedModel(_ url: URL? = nil) -> WorkspaceModel {
        let model = makeModel()
        model.openFolder(url ?? folder.url)
        return model
    }

    private func open(_ relativePath: String, in model: WorkspaceModel) async throws {
        await model.indexTask?.value
        model.open(try #require(model.fileIndex.first { $0.relativePath == relativePath }))
    }

    private func tabPaths(_ model: WorkspaceModel) -> [String] {
        model.tabs.map { $0.url.pathComponents.suffix(2).joined(separator: "/") }
    }

    // MARK: Store

    @Test func storeKeepsOneSessionPerFolder() {
        let store = TabSessionStore(defaults: defaults)
        let session = TabSession(files: ["a.md"], activeFile: "a.md", selections: ["a.md": NSRange(location: 2, length: 3)])

        store.save(session, for: folder.url)

        #expect(store.session(for: folder.url) == session)
        #expect(store.session(for: folder.url.appending(path: "docs")) == nil)
    }

    @Test func storeForgetsTheOldestFoldersPastItsLimit() {
        let store = TabSessionStore(defaults: defaults, limit: 2)
        let session = TabSession(files: ["a.md"], activeFile: nil, selections: [:])
        let folders = (1...3).map { URL(filePath: "/tmp/folder\($0)", directoryHint: .isDirectory) }

        folders.forEach { store.save(session, for: $0) }

        #expect(store.session(for: folders[0]) == nil)
        #expect(store.session(for: folders[2]) == session)
    }

    @Test func savingAnEmptySessionForgetsTheFolder() {
        let store = TabSessionStore(defaults: defaults)
        store.save(TabSession(files: ["a.md"], activeFile: nil, selections: [:]), for: folder.url)

        store.save(TabSession(files: [], activeFile: nil, selections: [:]), for: folder.url)

        #expect(store.session(for: folder.url) == nil)
    }

    // MARK: Restoring

    @Test func reopeningTheFolderRestoresItsTabsAndTheActiveOne() async throws {
        let first = openedModel()
        try await open("a.md", in: first)
        try await open("docs/c.md", in: first)
        try await open("b.json", in: first)
        first.activateTab(first.tabs[1].id)

        let second = openedModel()

        #expect(tabPaths(second) == tabPaths(first))
        #expect(second.document?.text == "Charlie")
        #expect(!second.hasUnsavedChanges)
    }

    @Test func restoresEachTabsSelectionWhenItIsShown() async throws {
        let first = openedModel()
        try await open("a.md", in: first)
        let aID = try #require(first.document?.id)
        first.noteSelection(NSRange(location: 6, length: 4), in: aID)
        try await open("b.json", in: first)
        first.saveTabSession() // as when the window closes

        let second = openedModel()
        #expect(second.document?.url.lastPathComponent == "b.json")

        second.activateTab(second.tabs[0].id)

        #expect(second.revealRequest?.range == NSRange(location: 6, length: 4))
        #expect(second.revealRequest?.focusesEditor == false)
        #expect(second.revealRequest?.highlights == false)
    }

    @Test func filesThatNoLongerExistAreSkipped() async throws {
        let first = openedModel()
        try await open("a.md", in: first)
        try await open("b.json", in: first)
        try FileManager.default.removeItem(at: folder.url.appending(path: "b.json"))

        let second = openedModel()

        #expect(second.tabs.map(\.url.lastPathComponent) == ["a.md"])
        #expect(second.document?.url.lastPathComponent == "a.md")
    }

    @Test func eachFolderKeepsItsOwnTabs() async throws {
        let other = try TemporaryDirectory()
        try other.makeFile("other.md", contents: "Other")
        let model = openedModel()
        try await open("a.md", in: model)

        model.openFolder(other.url)
        #expect(model.tabs.isEmpty)
        try await open("other.md", in: model)
        model.openFolder(folder.url)

        #expect(model.tabs.map(\.url.lastPathComponent) == ["a.md"])
        #expect(openedModel(other.url).tabs.map(\.url.lastPathComponent) == ["other.md"])
    }

    @Test func closingEveryTabIsRemembered() async throws {
        let first = openedModel()
        try await open("a.md", in: first)
        first.closeTab(first.tabs[0].id)

        #expect(openedModel().tabs.isEmpty)
    }

    @Test func theScratchpadIsNeverRestored() async throws {
        let first = openedModel()
        try await open("a.md", in: first)
        first.showScratchpad()
        first.updateScratchpadText("draft")
        first.saveTabSession()

        let second = openedModel()

        #expect(second.scratchpadText.isEmpty)
        #expect(!second.isScratchpadActive)
        #expect(second.tabs.count == 1)
    }
}
