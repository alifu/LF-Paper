//
//  AppDelegateTests.swift
//  LF-PaperTests
//

import AppKit
import Testing
@testable import LF_Paper

/// Quitting with unsaved changes: the answer to the prompt decides whether files are written or reverted.
@MainActor
final class AppDelegateTests {
    private let suiteName = "LFPaperTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let folder: TemporaryDirectory

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        folder = try TemporaryDirectory()
        try folder.makeFile("a.md", contents: "A")
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    /// A workspace with a.md open and edited.
    private func editedWorkspace() throws -> WorkspaceModel {
        let model = WorkspaceModel(
            bookmarkStore: BookmarkStore(defaults: defaults),
            recentFolders: RecentFolders(defaults: defaults),
            watchesFileSystem: false
        )
        model.openFolder(folder.url)
        model.selection = try #require(model.children(of: folder.url).first).url
        model.updateDocumentText("A edited")
        return model
    }

    @Test func quitsWithoutAskingWhenNothingIsUnsaved() {
        var asked = false

        let reply = AppDelegate.terminateReply(for: []) { _ in
            asked = true
            return .cancel
        }

        #expect(reply == .terminateNow)
        #expect(!asked)
    }

    @Test func saveWritesEveryFileAndQuits() throws {
        let workspace = try editedWorkspace()

        let reply = AppDelegate.terminateReply(for: [workspace]) { _ in .save }

        #expect(reply == .terminateNow)
        #expect(try folder.contents(of: "a.md") == "A edited")
    }

    @Test func dontSaveRevertsAndQuits() throws {
        let workspace = try editedWorkspace()

        let reply = AppDelegate.terminateReply(for: [workspace]) { _ in .discard }

        #expect(reply == .terminateNow)
        #expect(!workspace.hasUnsavedChanges)
        #expect(try folder.contents(of: "a.md") == "A")
    }

    @Test func cancelKeepsTheAppOpenAndTheEdits() throws {
        let workspace = try editedWorkspace()

        let reply = AppDelegate.terminateReply(for: [workspace]) { _ in .cancel }

        #expect(reply == .terminateCancel)
        #expect(workspace.hasUnsavedChanges)
    }

    @Test func aFailedSaveKeepsTheAppOpen() throws {
        let workspace = try editedWorkspace()
        try FileManager.default.removeItem(at: folder.url) // the file can't be written back any more

        let reply = AppDelegate.terminateReply(for: [workspace]) { _ in .save }

        #expect(reply == .terminateCancel)
        #expect(workspace.presentedError != nil)
    }
}
