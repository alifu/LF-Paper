//
//  FolderTree.swift
//  LF-Paper
//

import Foundation

/// The open folder's lazily loaded tree: which folders are listed and which are expanded.
/// Immutable: every change returns a new value. Listing a folder is passed in, so the tree
/// never touches the disk itself.
nonisolated struct FolderTree: Equatable, Sendable {
    /// Lists a folder's items.
    typealias Lister = (URL) throws(AppError) -> [FileItem]

    static let empty = FolderTree(root: nil, childrenByFolder: [:], expandedFolders: [])

    let root: URL?
    /// Loaded folder contents. Only the root and expanded folders are kept up to date.
    let childrenByFolder: [URL: [FileItem]]
    let expandedFolders: Set<URL>

    /// A tree showing only the root's items.
    static func opening(_ root: URL, items: [FileItem]) -> FolderTree {
        FolderTree(root: root, childrenByFolder: [root: items], expandedFolders: [])
    }

    func children(of folder: URL) -> [FileItem] {
        childrenByFolder[folder] ?? []
    }

    func isLoaded(_ folder: URL) -> Bool {
        childrenByFolder[folder] != nil
    }

    /// The loaded item at `url`, matched by path so spelling differences
    /// (like a trailing slash) don't matter.
    func item(at url: URL) -> FileItem? {
        childrenByFolder.values.lazy.flatMap { $0 }.first { $0.url.refersToSameFile(as: url) }
    }

    /// Lists `folder` (again), keeping everything else.
    func loading(_ folder: URL, using list: Lister) throws(AppError) -> FolderTree {
        var children = childrenByFolder
        children[folder] = try list(folder)
        return FolderTree(root: root, childrenByFolder: children, expandedFolders: expandedFolders)
    }

    func expanding(_ folder: URL) -> FolderTree {
        FolderTree(root: root, childrenByFolder: childrenByFolder, expandedFolders: expandedFolders.union([folder]))
    }

    func collapsing(_ folder: URL) -> FolderTree {
        FolderTree(root: root, childrenByFolder: childrenByFolder, expandedFolders: expandedFolders.subtracting([folder]))
    }

    /// Re-reads the root and every expanded folder, dropping anything that disappeared and
    /// every collapsed folder. A folder that can't be read is dropped too, and its error returned.
    func reloading(using list: Lister) -> (tree: FolderTree, errors: [AppError]) {
        guard let root else { return (self, []) }
        let folders = [root] + expandedFolders.filter { $0 != root }
        var reloaded: [URL: [FileItem]] = [:]
        var errors: [AppError] = []
        for folder in folders {
            do throws(AppError) {
                reloaded[folder] = try list(folder)
            } catch .fileNotFound {
                continue // Deleted or renamed outside the app.
            } catch {
                errors.append(error)
            }
        }
        let tree = FolderTree(
            root: root,
            childrenByFolder: reloaded,
            expandedFolders: expandedFolders.filter { reloaded[$0] != nil }
        )
        return (tree, errors)
    }

    /// Where "New File"/"New Folder" go: the folder itself, or the folder containing the file.
    func targetFolder(for item: FileItem?) -> URL? {
        guard let item else { return root }
        if item.isFolder { return item.url }
        return childrenByFolder.first { $0.value.contains(item) }?.key ?? item.url.deletingLastPathComponent()
    }
}
