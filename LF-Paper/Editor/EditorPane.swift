//
//  EditorPane.swift
//  LF-Paper
//

import SwiftUI

/// The editor column: the open document, or a hint when nothing is open.
struct EditorPane: View {
    let model: WorkspaceModel

    var body: some View {
        if let document = model.document {
            VStack(spacing: 0) {
                if model.isDocumentMissingOnDisk {
                    MissingFileBanner(fileName: document.url.lastPathComponent) {
                        _ = model.save()
                    }
                }
                if model.isJSONDocument {
                    JSONEditorBar(model: model)
                    Divider()
                }
                CodeTextView(
                    text: document.text,
                    documentID: document.id,
                    fileKind: FileKind(fileExtension: document.url.pathExtension),
                    revealRequest: model.revealRequest,
                    onTextChange: { model.updateDocumentText($0) }
                )
            }
        } else {
            ContentUnavailableView(
                "No File Selected",
                systemImage: "doc.text",
                description: Text("Select a Markdown or JSON file in the sidebar.")
            )
        }
    }
}

private struct MissingFileBanner: View {
    let fileName: String
    let onSave: () -> Void

    var body: some View {
        HStack {
            Label("“\(fileName)” was deleted from disk.", systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
            Spacer()
            Button("Save to Recreate", action: onSave)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.15))
    }
}
