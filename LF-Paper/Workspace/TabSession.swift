//
//  TabSession.swift
//  LF-Paper
//

import Foundation
import os

/// A folder's open tabs, remembered so they reopen with the folder.
/// Paths are relative to the folder, so the session survives the folder being moved.
nonisolated struct TabSession: Codable, Equatable, Sendable {
    /// In tab order.
    let files: [String]
    let activeFile: String?
    /// The editor selection of each tab.
    let selections: [String: NSRange]
}

/// Stores the tab sessions of the most recently used folders in the settings.
nonisolated struct TabSessionStore {
    static let storageKey = "workspace.tabSessions"
    static let defaultLimit = 30

    private static let logger = Logger(subsystem: "AppWork.LF-Paper", category: "TabSessions")

    private struct Entry: Codable {
        let folder: String
        let session: TabSession
    }

    private let defaults: UserDefaults
    private let limit: Int

    init(defaults: UserDefaults = .standard, limit: Int = TabSessionStore.defaultLimit) {
        self.defaults = defaults
        self.limit = limit
    }

    func session(for folder: URL) -> TabSession? {
        let key = Self.key(for: folder)
        return entries().first { $0.folder == key }?.session
    }

    /// Saving a session without tabs forgets the folder.
    func save(_ session: TabSession, for folder: URL) {
        let key = Self.key(for: folder)
        let others = entries().filter { $0.folder != key }
        let updated = session.files.isEmpty ? others : [Entry(folder: key, session: session)] + others
        do {
            defaults.set(try JSONEncoder().encode(Array(updated.prefix(limit))), forKey: Self.storageKey)
        } catch {
            Self.logger.error("Could not save open tabs: \(error.localizedDescription)")
        }
    }

    /// Newest first.
    private func entries() -> [Entry] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        do {
            return try JSONDecoder().decode([Entry].self, from: data)
        } catch {
            Self.logger.error("Forgetting unreadable open tabs: \(error.localizedDescription)")
            return []
        }
    }

    private static func key(for folder: URL) -> String {
        folder.standardizedFileURL.pathComponents.joined(separator: "/")
    }
}

extension URL {
    /// The path components below `ancestor`, or `nil` when this URL isn't inside it.
    nonisolated func components(below ancestor: URL) -> [String]? {
        let ancestorComponents = ancestor.standardizedFileURL.pathComponents
        let components = standardizedFileURL.pathComponents
        guard components.count > ancestorComponents.count,
              Array(components.prefix(ancestorComponents.count)) == ancestorComponents
        else { return nil }
        return Array(components.dropFirst(ancestorComponents.count))
    }
}
