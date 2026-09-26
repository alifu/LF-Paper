//
//  FileIndexer.swift
//  LF-Paper
//

import Foundation

/// A Markdown or JSON file somewhere under the open folder.
nonisolated struct IndexedFile: Hashable, Sendable, Identifiable {
    /// Spelled from the root URL, so it matches the URLs in the sidebar tree.
    let url: URL
    /// Path below the root with "/" separators, such as "docs/guide/setup.md".
    let relativePath: String
    let kind: FileKind

    var id: URL { url }
    var name: String { url.lastPathComponent }
    /// The folders above the file, or "" for a file at the root.
    var folderPath: String {
        let components = relativePath.split(separator: "/").dropLast()
        return components.joined(separator: "/")
    }

    /// `nil` when the path isn't a supported file type.
    init?(root: URL, relativePath: String) {
        guard let kind = FileKind(fileExtension: (relativePath as NSString).pathExtension) else { return nil }
        self.url = root.appending(path: relativePath, directoryHint: .notDirectory)
        self.relativePath = relativePath
        self.kind = kind
    }
}

/// Lists every supported file under a folder, for Quick Open and Search in Folder.
nonisolated enum FileIndexer {
    /// Folders that hold dependencies or build output rather than the user's documents.
    static let skippedFolderNames: Set<String> = ["node_modules", ".git", ".build", "DerivedData", "Pods", "Carthage"]
    /// A bound for huge folders (such as a home folder), so indexing stays quick.
    static let defaultLimit = 50_000

    private static let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]

    /// Sorted by path. Packages (like `.app` bundles) are skipped, and hidden items unless `includeHidden`.
    /// Stops early, returning what it found so far, when the task is cancelled.
    static func index(root: URL, includeHidden: Bool, limit: Int = defaultLimit) -> [IndexedFile] {
        let options: FileManager.DirectoryEnumerationOptions = includeHidden
            ? [.skipsPackageDescendants]
            : [.skipsPackageDescendants, .skipsHiddenFiles]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: resourceKeys, options: options) else {
            return []
        }
        let rootComponents = root.resolvingSymlinksInPath().pathComponents
        var files: [IndexedFile] = []
        while let url = enumerator.nextObject() as? URL, files.count < limit, !Task.isCancelled {
            let values = try? url.resourceValues(forKeys: Set(resourceKeys))
            if values?.isDirectory == true {
                if values?.isPackage == true || skippedFolderNames.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if let file = relativePath(of: url, below: rootComponents).flatMap({ IndexedFile(root: root, relativePath: $0) }) {
                files.append(file)
            }
        }
        return files.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    /// Compared after resolving symlinks, because the enumerator may spell the root differently
    /// (for example /private/var instead of /var).
    private static func relativePath(of url: URL, below rootComponents: [String]) -> String? {
        let components = url.resolvingSymlinksInPath().pathComponents
        guard components.count > rootComponents.count, Array(components.prefix(rootComponents.count)) == rootComponents else {
            return nil
        }
        return components.dropFirst(rootComponents.count).joined(separator: "/")
    }
}
