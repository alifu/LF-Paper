//
//  FilePath.swift
//  LF-Paper
//

import Foundation

/// One part of the path bar: a folder or the file itself.
nonisolated struct PathSegment: Equatable, Sendable, Identifiable {
    let name: String
    let url: URL
    let isFolder: Bool
    /// Inside the open folder, so it can be shown in the sidebar.
    let isInWorkspace: Bool

    var id: URL { url }
}

/// Splits a file's path for the path bar.
nonisolated enum FilePath {
    /// Inside `root`: the root's name, each folder, then the file. Elsewhere: the full path,
    /// starting with `~` for the home folder.
    static func segments(of file: URL, root: URL?, homeDirectory: URL) -> [PathSegment] {
        if let root, let below = file.components(below: root) {
            return segments(from: root, name: root.standardizedFileURL.lastPathComponent, below: below, isInWorkspace: true)
        }
        if let below = file.components(below: homeDirectory) {
            return segments(from: homeDirectory, name: "~", below: below, isInWorkspace: false)
        }
        let components = Array(file.standardizedFileURL.pathComponents.dropFirst()) // without "/"
        guard let first = components.first else { return [] }
        let start = URL(filePath: "/" + first, directoryHint: components.count > 1 ? .isDirectory : .notDirectory)
        return segments(from: start, name: first, below: Array(components.dropFirst()), isInWorkspace: false)
    }

    /// The path below `root` with "/" separators, or `nil` when the item isn't inside it.
    static func relativePath(of item: URL, root: URL?) -> String? {
        guard let root else { return nil }
        return item.components(below: root)?.joined(separator: "/")
    }

    private static func segments(from start: URL, name: String, below: [String], isInWorkspace: Bool) -> [PathSegment] {
        var segments = [PathSegment(name: name, url: start.standardizedFileURL, isFolder: !below.isEmpty, isInWorkspace: isInWorkspace)]
        var url = start.standardizedFileURL
        for (index, component) in below.enumerated() {
            let isFolder = index < below.count - 1
            url = url.appending(path: component, directoryHint: isFolder ? .isDirectory : .notDirectory)
            segments.append(PathSegment(name: component, url: url, isFolder: isFolder, isInWorkspace: isInWorkspace))
        }
        return segments
    }
}
