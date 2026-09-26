//
//  BookmarkStore.swift
//  LF-Paper
//

import Foundation
import os

/// Remembers the last opened folder across launches with a security-scoped bookmark,
/// which the sandbox requires to reopen a user-selected folder.
nonisolated struct BookmarkStore {
    static let lastFolderKey = "workspace.lastFolderBookmark"
    private static let logger = Logger(subsystem: "AppWork.LF-Paper", category: "Bookmarks")

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = BookmarkStore.lastFolderKey) {
        self.defaults = defaults
        self.key = key
    }

    /// Call while the folder is accessible (e.g. right after opening it).
    func save(_ folder: URL) throws(AppError) {
        do {
            let data = try folder.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(data, forKey: key)
        } catch {
            throw AppError.from(error, url: folder, fallback: AppError.accessDenied)
        }
    }

    /// The saved folder, or `nil` if none was saved. A bookmark that no longer resolves
    /// (e.g. the folder was deleted) is logged and forgotten.
    /// Stale bookmarks still resolve; they're refreshed when the folder is saved again on open.
    func restore() -> URL? {
        guard let data = defaults.data(forKey: key) else { return nil }
        var isStale = false
        do {
            return try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            Self.logger.notice("Forgetting unusable folder bookmark: \(error.localizedDescription)")
            clear()
            return nil
        }
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
