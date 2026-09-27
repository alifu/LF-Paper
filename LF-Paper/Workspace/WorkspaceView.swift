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
    @State private var closeGuard: WindowCloseGuard?
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @AppStorage(AppSettings.Key.autosaves) private var autosaves = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
        } detail: {
            VStack(spacing: 0) {
                DocumentTabBar(model: model)
                Divider()
                HSplitView {
                    // The scratchpad has no preview; it always gets the full width.
                    if model.editorLayout.showsEditor || model.isScratchpadActive {
                        EditorPane(model: model)
                            .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if model.editorLayout.showsPreview && !model.isScratchpadActive {
                        PreviewPane(model: model)
                            .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if model.isQuickOpenPresented {
                quickOpen
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
                .disabled(model.isScratchpadActive)
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
        .onChange(of: window) { attachCloseGuard() }
        .onChange(of: model.hasUnsavedChanges) { _, hasUnsavedChanges in
            window?.isDocumentEdited = hasUnsavedChanges // the dot in the close button
            attachCloseGuard() // in case SwiftUI set up the window again since
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window, (notification.object as? NSWindow) === window else { return }
            // The close guard has asked already; this only catches closes that skip it.
            model.saveAll()
            model.saveTabSession()
        }
        .onChange(of: autosaves, initial: true) { _, autosaves in
            model.autosaveDelay = autosaves ? AppSettings.autosaveDelay : nil
        }
        .onChange(of: model.searchFocusRequest) {
            columnVisibility = .all // Find in Folder needs the sidebar
        }
        .onChange(of: model.replace.focusRequest) {
            columnVisibility = .all // and so does Replace
        }
        .onChange(of: model.sidebarRevealRequest) {
            columnVisibility = .all // the path bar showed a folder or file in it
        }
        .sheet(isPresented: isReviewingReplacements) {
            ReplacePreviewSheet(model: model)
        }
        .sheet(item: $model.swiftModelGenerator) { session in
            SwiftModelSheet(model: model, session: session)
        }
        .focusedSceneValue(\.workspace, model)
        .task {
            WorkspaceRegistry.shared.register(model)
            openInitialFolder()
        }
    }

    /// The Quick Open panel near the top of the window; clicking outside it closes it.
    private var quickOpen: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.001)
                .onTapGesture { model.isQuickOpenPresented = false }
                .accessibilityHidden(true)
            QuickOpenPanel(model: model)
                .padding(.top, 48)
        }
    }

    /// Asks about unsaved changes (or saves them, per Settings) before the window closes.
    private func attachCloseGuard() {
        guard let window else { return }
        let guardian = closeGuard ?? WindowCloseGuard(model: model)
        closeGuard = guardian
        guardian.attach(to: window)
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
        if model.isScratchpadActive { return "Scratchpad" }
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

    private var isReviewingReplacements: Binding<Bool> {
        Binding(
            get: { model.replace.plan != nil },
            set: { isPresented in
                if !isPresented { model.replace.cancel() }
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
