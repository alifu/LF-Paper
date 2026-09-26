//
//  TestWorkspace.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

/// A workspace on a temporary folder whose bookmarks and recent folders go to a throwaway
/// defaults suite, so tests never touch the real app's settings.
@MainActor
final class TestWorkspace {
    let folder: TemporaryDirectory
    let model: WorkspaceModel
    private let suiteName = "LFPaperTests.\(UUID().uuidString)"

    init(files: [String: String] = [:]) throws {
        folder = try TemporaryDirectory()
        for (name, contents) in files {
            try folder.makeFile(name, contents: contents)
        }
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        model = WorkspaceModel(
            bookmarkStore: BookmarkStore(defaults: defaults),
            recentFolders: RecentFolders(defaults: defaults),
            watchesFileSystem: false
        )
        model.openFolder(folder.url)
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    /// Opens a top-level file in a tab.
    func open(_ name: String) throws {
        model.selection = try #require(model.children(of: folder.url).first { $0.name == name }).url
    }

    /// Opens a JSON file and waits until it has been validated.
    func openJSON(_ name: String) async throws {
        try open(name)
        await model.json.analysisTask?.value
    }
}
