//
//  WorkspaceCommands.swift
//  LF-Paper
//

import AppKit
import SwiftUI

extension FocusedValues {
    /// The workspace of the key window, for menu commands.
    @Entry var workspace: WorkspaceModel?
}

/// File, View and JSON menu commands that act on the key window's workspace.
struct WorkspaceCommands: Commands {
    @FocusedValue(\.workspace) private var workspace
    @Environment(\.openWindow) private var openWindow
    @AppStorage(AppSettings.Key.editorFontSize) private var fontSize = AppSettings.defaultFontSize
    @AppStorage(AppSettings.Key.jsonIndentation) private var indentation = JSONIndentationSetting.twoSpaces
    private let recentFolders = RecentFolders.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            newItems
            Divider()
            Button("New Window") { openWindow(id: LF_PaperApp.workspaceWindowID) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Open Folder…") { workspace?.isFolderPickerPresented = true }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(workspace == nil)
            openRecentMenu
        }
        CommandGroup(replacing: .saveItem) {
            Button(workspace?.document == nil ? "Close" : "Close Tab") { close() }
                .keyboardShortcut("w")
            Button("Save") { workspace?.save() }
                .keyboardShortcut("s")
                .disabled(workspace?.activeTabHasUnsavedChanges != true)
            Button("Save All") { workspace?.saveAll() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(workspace?.hasUnsavedChanges != true)
        }
        CommandGroup(after: .sidebar) {
            viewItems
        }
        CommandMenu("JSON") {
            jsonItems
        }
    }

    // MARK: File

    @ViewBuilder
    private var newItems: some View {
        ForEach(NewFileType.allCases, id: \.self) { type in
            Button(type.menuTitle) {
                if let workspace, let folder = workspace.newItemFolder {
                    workspace.createFile(in: folder, type: type)
                }
            }
            .keyboardShortcut("n", modifiers: type == .markdown ? .command : [.command, .option])
        }
        .disabled(workspace?.newItemFolder == nil)
        Button("New Folder") {
            if let workspace, let folder = workspace.newItemFolder {
                workspace.createFolder(in: folder)
            }
        }
        .keyboardShortcut("n", modifiers: [.command, .control])
        .disabled(workspace?.newItemFolder == nil)
    }

    private var openRecentMenu: some View {
        Menu("Open Recent") {
            ForEach(recentFolders.folders, id: \.self) { folder in
                Button(folder.lastPathComponent) { workspace?.openFolder(folder) }
                    .help(folder.path(percentEncoded: false))
            }
            Divider()
            Button("Clear Menu") { recentFolders.clear() }
                .disabled(recentFolders.folders.isEmpty)
        }
        .disabled(workspace == nil)
    }

    /// Closes the active tab, or the window when no file is open (or another window is in front).
    private func close() {
        if let workspace, workspace.document != nil {
            workspace.closeActiveTab()
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }

    // MARK: View

    @ViewBuilder
    private var viewItems: some View {
        Toggle("Show Hidden Files", isOn: showsHiddenFiles)
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(workspace == nil)
        Button(workspace?.editorLayout.showsPreview == true ? "Hide Preview" : "Show Preview") {
            if let workspace {
                workspace.editorLayout = workspace.editorLayout.togglingPreview()
            }
        }
        .keyboardShortcut("p", modifiers: [.command, .option])
        .disabled(workspace == nil)
        Divider()
        Button("Show Next Tab") { workspace?.activateNextTab() }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled((workspace?.tabs.count ?? 0) < 2)
        Button("Show Previous Tab") { workspace?.activatePreviousTab() }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled((workspace?.tabs.count ?? 0) < 2)
        Divider()
        Button("Bigger") { fontSize = AppSettings.fontSize(fontSize, zoomed: .bigger) }
            .keyboardShortcut("+")
            .disabled(fontSize >= AppSettings.fontSizeRange.upperBound)
        Button("Smaller") { fontSize = AppSettings.fontSize(fontSize, zoomed: .smaller) }
            .keyboardShortcut("-")
            .disabled(fontSize <= AppSettings.fontSizeRange.lowerBound)
        Button("Actual Size") { fontSize = AppSettings.fontSize(fontSize, zoomed: .actualSize) }
            .keyboardShortcut("0")
            .disabled(fontSize == AppSettings.defaultFontSize)
    }

    private var showsHiddenFiles: Binding<Bool> {
        Binding(
            get: { workspace?.showsHiddenFiles ?? false },
            set: { workspace?.showsHiddenFiles = $0 }
        )
    }

    // MARK: JSON

    @ViewBuilder
    private var jsonItems: some View {
        Group {
            Button("Format") { workspace?.formatJSON(indentation: indentation.indentation) }
                .keyboardShortcut("f", modifiers: [.option, .shift])
            Button("Format with Sorted Keys") { workspace?.formatJSON(indentation: indentation.indentation, sortsKeys: true) }
            Button("Minify") { workspace?.minifyJSON() }
        }
        .disabled(workspace?.isJSONDocument != true)
        Divider()
        Button("Compare…") { openWindow(id: CompareView.windowID) }
            .keyboardShortcut("c", modifiers: [.command, .option])
    }
}
