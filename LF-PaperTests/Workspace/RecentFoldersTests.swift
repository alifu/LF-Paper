//
//  RecentFoldersTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

@MainActor
final class RecentFoldersTests {
    private let suiteName = "LFPaperTests.\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    private func names(_ recents: RecentFolders) -> [String] {
        recents.folders.map(\.lastPathComponent)
    }

    private func makeFolders(_ count: Int) throws -> [TemporaryDirectory] {
        try (0..<count).map { _ in try TemporaryDirectory() }
    }

    @Test func newestFolderComesFirstWithoutDuplicates() throws {
        let (a, b) = try (TemporaryDirectory(), TemporaryDirectory())
        let recents = RecentFolders(defaults: defaults)

        recents.add(a.url)
        recents.add(b.url)
        recents.add(a.url)

        #expect(names(recents) == [a.url.lastPathComponent, b.url.lastPathComponent])
    }

    @Test func keepsOnlyTheMostRecentFolders() throws {
        let folders = try makeFolders(4)
        let recents = RecentFolders(defaults: defaults, limit: 3)

        folders.forEach { recents.add($0.url) }

        #expect(names(recents) == folders.reversed().prefix(3).map(\.url.lastPathComponent))
    }

    @Test func survivesARelaunch() throws {
        let folder = try TemporaryDirectory()
        RecentFolders(defaults: defaults).add(folder.url)

        let relaunched = RecentFolders(defaults: defaults)

        #expect(names(relaunched) == [folder.url.lastPathComponent])
    }

    @Test func foldersThatNoLongerExistAreDropped() throws {
        var gone: TemporaryDirectory? = try TemporaryDirectory()
        let kept = try TemporaryDirectory()
        let recents = RecentFolders(defaults: defaults)
        recents.add(try #require(gone).url)
        recents.add(kept.url)
        gone = nil // deletes the folder

        let relaunched = RecentFolders(defaults: defaults)

        #expect(names(relaunched) == [kept.url.lastPathComponent])
    }

    @Test func clearForgetsEverything() throws {
        let folder = try TemporaryDirectory()
        let recents = RecentFolders(defaults: defaults)
        recents.add(folder.url)

        recents.clear()

        #expect(recents.folders.isEmpty)
        #expect(RecentFolders(defaults: defaults).folders.isEmpty)
    }

    @Test func openingAFolderInAWorkspaceAddsItToRecents() throws {
        let folder = try TemporaryDirectory()
        let recents = RecentFolders(defaults: defaults)
        let model = WorkspaceModel(
            fileService: LocalFileService(),
            bookmarkStore: BookmarkStore(defaults: defaults),
            recentFolders: recents,
            watchesFileSystem: false
        )

        model.openFolder(folder.url)

        #expect(names(recents) == [folder.url.lastPathComponent])
    }
}
