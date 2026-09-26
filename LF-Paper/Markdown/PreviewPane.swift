//
//  PreviewPane.swift
//  LF-Paper
//

import SwiftUI

/// The preview column: rendered Markdown, or the tree for JSON.
struct PreviewPane: View {
    let model: WorkspaceModel

    var body: some View {
        if let document = model.document {
            switch FileKind(fileExtension: document.url.pathExtension) {
            case .markdown:
                MarkdownPreviewView(
                    markdown: document.text,
                    documentURL: document.url,
                    workspaceRoot: model.rootURL
                )
            case .json:
                JSONTreePane(model: model)
            case .folder, nil:
                ContentUnavailableView(
                    "No Preview",
                    systemImage: "eye.slash",
                    description: Text("Preview is available for Markdown and JSON files.")
                )
            }
        } else {
            ContentUnavailableView(
                "Preview",
                systemImage: "eye",
                description: Text("Open a Markdown or JSON file to preview it here.")
            )
        }
    }
}
