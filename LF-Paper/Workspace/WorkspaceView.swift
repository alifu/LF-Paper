//
//  WorkspaceView.swift
//  LF-Paper
//

import SwiftUI
import UniformTypeIdentifiers

/// Main window: folder sidebar | editor | optional preview.
struct WorkspaceView: View {
    @State private var model = WorkspaceModel()
    @State private var isPreviewVisible = true

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
        } detail: {
            HSplitView {
                ReadOnlyDocumentView(document: model.document)
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                if isPreviewVisible {
                    PreviewPlaceholder()
                        .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle(model.rootURL?.lastPathComponent ?? "LF-Paper")
        .navigationSubtitle(model.document?.url.lastPathComponent ?? "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $isPreviewVisible) {
                    Label("Preview", systemImage: "sidebar.right")
                }
                .help("Show or hide the preview")
            }
        }
        .fileImporter(
            isPresented: $model.isFolderPickerPresented,
            allowedContentTypes: [.folder],
            onCompletion: model.handleFolderPickerResult
        )
        .alert(isPresented: isShowingError, error: model.presentedError) { _ in
            Button("OK") {}
        } message: { error in
            Text(error.recoverySuggestion ?? "")
        }
        .focusedSceneValue(\.workspace, model)
        .task { model.restoreLastFolder() }
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { model.presentedError != nil },
            set: { isPresented in
                if !isPresented { model.presentedError = nil }
            }
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
