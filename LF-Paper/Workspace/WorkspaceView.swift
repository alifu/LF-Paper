//
//  WorkspaceView.swift
//  LF-Paper
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Main window: folder sidebar | editor | optional preview.
struct WorkspaceView: View {
    @State private var model = WorkspaceModel()
    @State private var window: NSWindow?

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
        } detail: {
            HSplitView {
                if model.editorLayout.showsEditor {
                    EditorPane(model: model)
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                }
                if model.editorLayout.showsPreview {
                    PreviewPane(model: model)
                        .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle(model.rootURL?.lastPathComponent ?? "LF-Paper")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Layout", selection: $model.editorLayout) {
                    ForEach(EditorLayout.allCases) { layout in
                        Label(layout.title, systemImage: layout.systemImage).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .help("Editor, editor and preview, or preview only (⌥⌘P shows or hides the preview)")
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
        .alert(unsavedChangesMessage, isPresented: isAskingAboutUnsavedChanges) {
            Button(UnsavedChangesPrompt.saveTitle) { model.resolvePendingAction(.save) }
            Button(UnsavedChangesPrompt.discardTitle, role: .destructive) { model.resolvePendingAction(.discard) }
            Button(UnsavedChangesPrompt.cancelTitle, role: .cancel) { model.resolvePendingAction(.cancel) }
        } message: {
            Text(UnsavedChangesPrompt.informativeText)
        }
        .background(WindowReader { window = $0 })
        .onChange(of: model.hasUnsavedChanges) { _, hasUnsavedChanges in
            window?.isDocumentEdited = hasUnsavedChanges // the dot in the close button
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window, (notification.object as? NSWindow) === window else { return }
            // SwiftUI can't cancel a window close, so keep the user's work rather than lose it.
            _ = model.save()
        }
        .focusedSceneValue(\.workspace, model)
        .task {
            WorkspaceRegistry.shared.register(model)
            model.restoreLastFolder()
        }
    }

    private var subtitle: String {
        guard let name = model.document?.url.lastPathComponent else { return "" }
        return model.hasUnsavedChanges ? "\(name) — Edited" : name
    }

    private var unsavedChangesMessage: String {
        UnsavedChangesPrompt.message(fileName: model.document?.url.lastPathComponent ?? "this file")
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { model.presentedError != nil },
            set: { isPresented in
                if !isPresented { model.presentedError = nil }
            }
        )
    }

    private var isAskingAboutUnsavedChanges: Binding<Bool> {
        Binding(
            get: { model.pendingAction != nil },
            set: { isPresented in
                // Dismissed without choosing (e.g. Escape) counts as Cancel.
                if !isPresented { model.resolvePendingAction(.cancel) }
            }
        )
    }
}

#Preview {
    WorkspaceView()
        .frame(width: 1000, height: 640)
}
