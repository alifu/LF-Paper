//
//  FileItem.swift
//  LF-Paper
//

import Foundation

/// The kinds of items the workspace shows. Other files are hidden from the tree.
nonisolated enum FileKind: Sendable, Equatable {
    case folder
    case markdown
    case json
    /// Shown and edited as plain text; converts to and from JSON.
    case yaml
    case csv

    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]
    private static let jsonExtensions: Set<String> = ["json"]
    private static let yamlExtensions: Set<String> = ["yaml", "yml"]
    private static let csvExtensions: Set<String> = ["csv"]

    /// The kind for a file with this extension, or `nil` if the workspace doesn't support it.
    init?(fileExtension: String) {
        let lowercased = fileExtension.lowercased()
        if Self.markdownExtensions.contains(lowercased) {
            self = .markdown
        } else if Self.jsonExtensions.contains(lowercased) {
            self = .json
        } else if Self.yamlExtensions.contains(lowercased) {
            self = .yaml
        } else if Self.csvExtensions.contains(lowercased) {
            self = .csv
        } else {
            return nil
        }
    }

    /// What VoiceOver says after the name.
    var accessibilityName: String {
        switch self {
        case .folder: "folder"
        case .markdown: "Markdown file"
        case .json: "JSON file"
        case .yaml: "YAML file"
        case .csv: "CSV file"
        }
    }

    var systemImage: String {
        switch self {
        case .folder: "folder"
        case .markdown: "doc.richtext"
        case .json: "curlybraces"
        case .yaml: "list.bullet.indent"
        case .csv: "tablecells"
        }
    }
}

/// One file or folder in the workspace tree.
nonisolated struct FileItem: Identifiable, Hashable, Sendable {
    let url: URL
    let kind: FileKind

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var isFolder: Bool { kind == .folder }
}
