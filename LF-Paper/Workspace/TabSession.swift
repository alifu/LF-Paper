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

nonisolated extension TabSession {
    /// The session for `tabs` in the folder at `root`. Tabs outside the folder aren't remembered.
    static func make(from tabs: DocumentTabs, root: URL, selections: [UUID: NSRange]) -> TabSession {
        let paths = Dictionary(uniqueKeysWithValues: tabs.documents.compactMap { document in
            document.url.components(below: root).map { (document.id, $0.joined(separator: "/")) }
        })
        let selectionsByPath = Dictionary(uniqueKeysWithValues: paths.compactMap { id, path in
            selections[id].map { (path, $0) }
        })
        return TabSession(
            files: tabs.documents.compactMap { paths[$0.id] },
            activeFile: tabs.active.flatMap { paths[$0.id] },
            selections: selectionsByPath
        )
    }

    /// Reopens the session's tabs in `folder`. `read` returns a file's text, or `nil` when
    /// it's gone or unreadable; such files are skipped. Also returns each tab's remembered
    /// selection, to put back when the tab first shows.
    func restore(in folder: URL, reading read: (URL) -> String?) -> (tabs: DocumentTabs, pendingSelections: [UUID: NSRange]) {
        var restored = DocumentTabs.empty
        var pending: [UUID: NSRange] = [:]
        var activeID: UUID?
        for path in files {
            let url = folder.appending(path: path, directoryHint: .notDirectory)
            guard let text = read(url) else { continue }
            let document = OpenDocument(url: url, text: text)
            restored = restored.opening(document)
            pending[document.id] = selections[path]
            if path == activeFile { activeID = document.id }
        }
        return (activeID.map(restored.activating) ?? restored, pending)
    }
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
