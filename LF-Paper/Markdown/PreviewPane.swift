//
//  PreviewPane.swift
//  LF-Paper
//

import SwiftUI

/// The preview column: rendered Markdown, or a hint for other files.
struct PreviewPane: View {
    let model: WorkspaceModel

    var body: some View {
        if let document = model.document {
            if FileKind(fileExtension: document.url.pathExtension) == .markdown {
                MarkdownPreviewView(
                    markdown: document.text,
                    documentURL: document.url,
                    workspaceRoot: model.rootURL
                )
            } else {
                ContentUnavailableView(
                    "No Preview",
                    systemImage: "eye.slash",
                    description: Text("Preview is available for Markdown files.")
                )
            }
        } else {
            ContentUnavailableView(
                "Preview",
                systemImage: "eye",
                description: Text("Open a Markdown file to see it rendered here.")
            )
        }
    }
}
