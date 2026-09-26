//
//  EditorLayout.swift
//  LF-Paper
//

import Foundation

/// Which panes the detail area shows.
nonisolated enum EditorLayout: String, CaseIterable, Identifiable, Sendable {
    case editor
    case split
    case preview

    var id: Self { self }

    var title: String {
        switch self {
        case .editor: "Editor Only"
        case .split: "Editor and Preview"
        case .preview: "Preview Only"
        }
    }

    var systemImage: String {
        switch self {
        case .editor: "doc.plaintext"
        case .split: "rectangle.split.2x1"
        case .preview: "eye"
        }
    }

    var showsEditor: Bool { self != .preview }
    var showsPreview: Bool { self != .editor }

    /// ⌘⌥P: show the preview next to the editor, or hide it. From preview-only, go back to editing.
    func togglingPreview() -> EditorLayout {
        self == .editor ? .split : .editor
    }
}
