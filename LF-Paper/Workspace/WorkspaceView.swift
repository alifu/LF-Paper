//
//  WorkspaceView.swift
//  LF-Paper
//

import SwiftUI

/// Main window: folder sidebar | editor | optional preview.
struct WorkspaceView: View {
    @State private var isPreviewVisible = true

    var body: some View {
        NavigationSplitView {
            SidebarPlaceholder()
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
        } detail: {
            HSplitView {
                EditorPlaceholder()
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                if isPreviewVisible {
                    PreviewPlaceholder()
                        .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $isPreviewVisible) {
                    Label("Preview", systemImage: "sidebar.right")
                }
                .help("Show or hide the preview")
            }
        }
    }
}

private struct SidebarPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "No Folder Open",
            systemImage: "folder",
            description: Text("Open a folder to browse its files.")
        )
    }
}

private struct EditorPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "No File Selected",
            systemImage: "doc.text",
            description: Text("Select a Markdown or JSON file in the sidebar.")
        )
    }
}

private struct PreviewPlaceholder: View {
    var body: some View {
        ContentUnavailableView("Preview", systemImage: "eye")
            .background(.background.secondary)
    }
}

#Preview {
    WorkspaceView()
        .frame(width: 1000, height: 640)
}
