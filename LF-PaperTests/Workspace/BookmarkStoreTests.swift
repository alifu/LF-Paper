//
//  BookmarkStoreTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

final class BookmarkStoreTests {
    private let suiteName = "LFPaperTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let folder: TemporaryDirectory
    private let store: BookmarkStore

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        folder = try TemporaryDirectory()
        store = BookmarkStore(defaults: defaults)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func restoreReturnsNilWhenNothingWasSaved() {
        #expect(store.restore() == nil)
    }

    @Test func savedFolderRestoresToTheSameLocation() throws {
        try store.save(folder.url)

        let restored = try #require(store.restore())

        #expect(restored.resolvingSymlinksInPath().path == folder.url.resolvingSymlinksInPath().path)
    }

    @Test func corruptBookmarkRestoresNilAndIsCleared() {
        defaults.set(Data("not a bookmark".utf8), forKey: BookmarkStore.lastFolderKey)

        #expect(store.restore() == nil)
        #expect(defaults.data(forKey: BookmarkStore.lastFolderKey) == nil)
    }

    @Test func clearForgetsTheSavedFolder() throws {
        try store.save(folder.url)

        store.clear()

        #expect(store.restore() == nil)
    }
}
