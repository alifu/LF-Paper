//
//  FileTreeRow.swift
//  LF-Paper
//

import SwiftUI

/// One row in the sidebar tree. Folders load their children the first time they're expanded.
struct FileTreeRow: View {
    let item: FileItem
    let model: WorkspaceModel

    var body: some View {
        if item.isFolder {
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(model.children(of: item.url)) { child in
                    FileTreeRow(item: child, model: model)
                }
            } label: {
                FileLabel(item: item)
            }
        } else {
            FileLabel(item: item)
        }
    }

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { model.expandedFolders.contains(item.url) },
            set: { model.setExpanded(item.url, $0) }
        )
    }
}

private struct FileLabel: View {
    let item: FileItem

    var body: some View {
        Label(item.name, systemImage: item.kind.systemImage)
            .lineLimit(1)
            .truncationMode(.middle)
            .accessibilityLabel("\(item.name), \(item.kind.accessibilityName)")
            .accessibilityIdentifier("file-\(item.name)")
    }
}
