//
//  SidebarView.swift
//  LF-Paper
//

import AppKit
import SwiftUI

/// The folder navigator: a file tree with a context menu for creating, renaming and trashing items.
struct SidebarView: View {
    @Bindable var model: WorkspaceModel
    @State private var renameTarget: FileItem?
    @State private var proposedName = ""
    @State private var trashTarget: FileItem?

    var body: some View {
        content
            .alert("Rename", isPresented: isPresenting($renameTarget), presenting: renameTarget) { item in
                TextField("Name", text: $proposedName)
                Button("Rename") { model.rename(item, to: proposedName) }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Move to Trash?",
                isPresented: isPresenting($trashTarget),
                presenting: trashTarget
            ) { item in
                Button("Move “\(item.name)” to Trash", role: .destructive) {
                    model.moveToTrash(item)
                }
            } message: { _ in
                Text("You can restore it from the Trash in Finder.")
            }
    }

    @ViewBuilder
    private var content: some View {
        if let rootURL = model.rootURL {
            fileList(root: rootURL)
        } else {
            emptyState
        }
    }

    private func fileList(root: URL) -> some View {
        List(selection: $model.selection) {
            ForEach(model.children(of: root)) { item in
                FileTreeRow(item: item, model: model)
            }
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            menu(for: urls.first.flatMap(model.item(at:)))
        } primaryAction: { urls in
            toggleFolder(at: urls.first)
        }
        .onDeleteCommand {
            trashTarget = model.selection.flatMap(model.item(at:))
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Folder Open", systemImage: "folder")
        } description: {
            Text("Open a folder to browse its Markdown and JSON files.")
        } actions: {
            Button("Open Folder…") { model.isFolderPickerPresented = true }
        }
    }

    /// Menu for a clicked item, or for the empty area below the tree when `item` is nil.
    @ViewBuilder
    private func menu(for item: FileItem?) -> some View {
        if let folder = model.targetFolder(for: item) {
            Button("New File") { model.createFile(in: folder) }
            Button("New Folder") { model.createFolder(in: folder) }
        }
        if let item {
            Divider()
            Button("Rename…") { beginRename(item) }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Divider()
            Button("Move to Trash", role: .destructive) { trashTarget = item }
        }
    }

    private func beginRename(_ item: FileItem) {
        proposedName = item.name
        renameTarget = item
    }

    private func toggleFolder(at url: URL?) {
        guard let url, let item = model.item(at: url), item.isFolder else { return }
        model.setExpanded(item.url, !model.expandedFolders.contains(item.url))
    }

    private func isPresenting(_ target: Binding<FileItem?>) -> Binding<Bool> {
        Binding(
            get: { target.wrappedValue != nil },
            set: { isPresented in
                if !isPresented { target.wrappedValue = nil }
            }
        )
    }
}
