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
    @State private var model = Self.makeModel()
    @State private var window: NSWindow?
    @AppStorage(AppSettings.Key.autosaves) private var autosaves = false

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
        } detail: {
            VStack(spacing: 0) {
                if !model.tabs.isEmpty {
                    DocumentTabBar(model: model)
                    Divider()
                }
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
            model.saveAll()
        }
        .onChange(of: autosaves, initial: true) { _, autosaves in
            model.autosaveDelay = autosaves ? AppSettings.autosaveDelay : nil
        }
        .focusedSceneValue(\.workspace, model)
        .task {
            WorkspaceRegistry.shared.register(model)
            openInitialFolder()
        }
    }

    private static func makeModel() -> WorkspaceModel {
        #if DEBUG
        if UITestSupport.isActive { return UITestSupport.makeModel() }
        #endif
        return WorkspaceModel()
    }

    private func openInitialFolder() {
        #if DEBUG
        if UITestSupport.isActive, let fixture = UITestSupport.makeFixtureFolder() {
            model.openFolder(fixture)
            return
        }
        #endif
        model.restoreLastFolder()
    }

    private var subtitle: String {
        guard let name = model.document?.url.lastPathComponent else { return "" }
        return model.activeTabHasUnsavedChanges ? "\(name) — Edited" : name
    }

    private var unsavedChangesMessage: String {
        UnsavedChangesPrompt.message(for: model.pendingActionDocuments)
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
        .environment(CompareModel())
        .frame(width: 1000, height: 640)
}
