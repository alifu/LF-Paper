//
//  WorkspaceModel+PathBar.swift
//  LF-Paper
//

import AppKit

/// The path bar above the editor: where the open file is, and its actions.
extension WorkspaceModel {
    /// The open file's path, or nothing while the scratchpad shows or no file is open.
    var pathSegments: [PathSegment] {
        guard let document else { return [] }
        return FilePath.segments(of: document.url, root: rootURL, homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// Shows a folder or file in the Files sidebar, expanding the folders above it, and selects it.
    /// The open folder itself only switches the sidebar to Files.
    func showInSidebar(_ url: URL) {
        sidebarMode = .files
        requestSidebar()
        guard let treeURL = revealInTree(url) else { return }
        selection = treeURL
    }

    /// The full path, or the path below the open folder.
    func copyPath(of url: URL, relative: Bool, to pasteboard: NSPasteboard = .general) {
        let path = relative ? FilePath.relativePath(of: url, root: rootURL) : url.path(percentEncoded: false)
        guard let path else { return }
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([finderTarget(for: url)])
    }

    /// The item itself, or its folder when it isn't on disk yet (a new, unsaved file).
    func finderTarget(for url: URL) -> URL {
        fileService.exists(url) ? url : url.deletingLastPathComponent()
    }
}
