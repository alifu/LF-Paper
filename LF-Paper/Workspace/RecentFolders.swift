//
//  RecentFolders.swift
//  LF-Paper
//

import Foundation
import Observation
import os

/// The most recently opened folders, newest first, for File › Open Recent.
/// Stored as security-scoped bookmarks, which the sandbox needs to reopen them later.
@Observable
final class RecentFolders {
    static let shared = RecentFolders()
    static let storageKey = "workspace.recentFolderBookmarks"
    static let defaultLimit = 10

    private static let logger = Logger(subsystem: "AppWork.LF-Paper", category: "RecentFolders")

    /// Resolved folders, newest first. Folders that no longer exist are left out.
    private(set) var folders: [URL] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let limit: Int
    @ObservationIgnored private var bookmarks: [Data] = []

    init(defaults: UserDefaults = .standard, limit: Int = RecentFolders.defaultLimit) {
        self.defaults = defaults
        self.limit = limit
        load()
    }

    /// Call while the folder is accessible (e.g. right after opening it).
    func add(_ folder: URL) {
        let bookmark: Data
        do {
            bookmark = try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            Self.logger.error("Could not add a recent folder: \(error.localizedDescription)")
            return
        }
        let others = zip(bookmarks, folders).filter { !$0.1.refersToSameFile(as: folder) }
        let entries = ([(bookmark, folder)] + others).prefix(limit)
        bookmarks = entries.map(\.0)
        folders = entries.map(\.1)
        save()
    }

    func clear() {
        bookmarks = []
        folders = []
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func load() {
        let stored = defaults.array(forKey: Self.storageKey) as? [Data] ?? []
        let resolved = stored.compactMap { data in Self.resolve(data).map { (data, $0) } }
        bookmarks = resolved.map(\.0)
        folders = resolved.map(\.1)
        if resolved.count != stored.count {
            save() // forget folders that are gone
        }
    }

    private func save() {
        defaults.set(bookmarks, forKey: Self.storageKey)
    }

    private static func resolve(_ bookmark: Data) -> URL? {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale),
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        else { return nil }
        return url
    }
}
