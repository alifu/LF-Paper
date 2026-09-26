//
//  WorkspaceRegistryTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

@MainActor
final class WorkspaceRegistryTests {
    private let suiteName = "LFPaperTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let folder: TemporaryDirectory
    private let registry = WorkspaceRegistry()

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        folder = try TemporaryDirectory()
        try folder.makeFile("a.md", contents: "A")
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    private func makeModel(editing: Bool) throws -> WorkspaceModel {
        let model = WorkspaceModel(
            bookmarkStore: BookmarkStore(defaults: defaults),
            watchesFileSystem: false
        )
        model.openFolder(folder.url)
        model.selection = try #require(model.children(of: folder.url).first).url
        if editing {
            model.updateDocumentText("A edited")
        }
        return model
    }

    @Test func reportsOnlyWorkspacesWithUnsavedChanges() throws {
        let clean = try makeModel(editing: false)
        let dirty = try makeModel(editing: true)

        registry.register(clean)
        registry.register(dirty)

        #expect(registry.workspacesWithUnsavedChanges.map(ObjectIdentifier.init) == [ObjectIdentifier(dirty)])
    }

    @Test func registeringTheSameWorkspaceTwiceListsItOnce() throws {
        let dirty = try makeModel(editing: true)

        registry.register(dirty)
        registry.register(dirty)

        #expect(registry.workspacesWithUnsavedChanges.count == 1)
    }
}
