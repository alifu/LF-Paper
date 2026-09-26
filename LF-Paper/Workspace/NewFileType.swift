//
//  NewFileType.swift
//  LF-Paper
//

import Foundation

/// The kinds of file "New File" can create.
nonisolated enum NewFileType: CaseIterable, Sendable {
    case markdown
    case json

    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .json: "json"
        }
    }

    /// What a new file starts with. An empty file isn't valid JSON, so JSON starts as `{}`.
    var initialContents: String {
        switch self {
        case .markdown: ""
        case .json: "{}\n"
        }
    }

    var menuTitle: String {
        switch self {
        case .markdown: "New Markdown File"
        case .json: "New JSON File"
        }
    }
}
