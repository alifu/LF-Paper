//
//  WorkspaceModel+Navigation.swift
//  LF-Paper
//

import Foundation

/// Quick Open: finding a file anywhere in the folder and opening it.
extension WorkspaceModel {
    /// How many results the Quick Open list shows.
    static let quickOpenLimit = 50

    func quickOpenResults(for query: String) -> [QuickOpenResult] {
        QuickOpenRanking.rank(query: query, files: fileIndex, recent: recentFiles, limit: Self.quickOpenLimit)
    }

    /// Opens an indexed file in a tab, expanding its folders in the sidebar so it shows there too.
    func open(_ file: IndexedFile) {
        isQuickOpenPresented = false
        selection = revealInTree(file.url) ?? file.url
    }

    /// Expands the folders above `url`, loading them as needed, and returns the tree's URL for the file.
    /// Returns `nil` when the file is outside the folder or no longer listed.
    func revealInTree(_ url: URL) -> URL? {
        guard let rootURL, let components = url.components(below: rootURL) else { return nil }

        var folder = rootURL
        for name in components.dropLast() {
            guard let item = children(of: folder).first(where: { $0.isFolder && $0.name == name }) else { return nil }
            setExpanded(item.url, true)
            folder = item.url
        }
        return children(of: folder).first { $0.name == url.lastPathComponent }?.url
    }
}

/// What the sidebar shows.
enum SidebarMode: Hashable {
    case files
    case search
    /// The headings of the Markdown file being edited.
    case outline
}

/// Search in Folder: running a search over the indexed files and opening a match.
extension WorkspaceModel {
    /// Searches every indexed file, using the unsaved text of open files.
    /// Waits for indexing that's still running, such as right after a folder opens.
    func runFolderSearch() {
        let pendingIndex = indexTask
        search.start { [weak self] in
            await pendingIndex?.value
            return self?.searchTargets() ?? []
        }
    }

    /// Opens the file and selects the match in the editor.
    func open(_ match: TextMatch, in result: FileSearchResult) {
        open(result.file)
        reveal(match.range, focusesEditor: true)
    }

    /// The text of every open tab (edited or not) by standardized URL: what search and replace see.
    func openTextsByURL() -> [URL: String] {
        Dictionary(tabs.map { ($0.url.standardizedFileURL, $0.text) }, uniquingKeysWith: { first, _ in first })
    }

    private func searchTargets() -> [SearchTarget] {
        let openTexts = openTextsByURL()
        return fileIndex.map { SearchTarget(file: $0, unsavedText: openTexts[$0.url.standardizedFileURL]) }
    }
}
