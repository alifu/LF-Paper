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
    /// The Compare window's model, for Compare with Saved Version.
    let compare: CompareModel
    @FocusedValue(\.workspace) private var workspace
    @Environment(\.openWindow) private var openWindow
    @AppStorage(AppSettings.Key.editorFontSize) private var fontSize = AppSettings.defaultFontSize
    @AppStorage(AppSettings.Key.wrapsLines) private var wrapsLines = AppSettings.defaultWrapsLines
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
        CommandGroup(replacing: .printItem) {
            Button("Quick Open…") { workspace?.isQuickOpenPresented = true }
                .keyboardShortcut("p")
                .disabled(workspace?.rootURL == nil)
            Button("Find in Folder…") { workspace?.showFolderSearch() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(workspace?.rootURL == nil)
            Button("Replace in Folder…") { workspace?.showFolderReplace() }
                .keyboardShortcut("f", modifiers: [.command, .option, .shift])
                .disabled(workspace?.rootURL == nil)
        }
        CommandGroup(after: .undoRedo) {
            // Tabs edited by Replace All undo with their own ⌘Z; this puts back the files it wrote.
            Button("Undo Replace All") { workspace?.undoReplaceAll() }
                .disabled(workspace?.replace.canUndo != true)
        }
        CommandGroup(replacing: .saveItem) {
            Button(workspace?.document == nil ? "Close" : "Close Tab") { close() }
                .keyboardShortcut("w")
                .disabled(workspace?.isScratchpadActive == true) // the Scratch tab can't be closed
            Button("Save") { workspace?.save() }
                .keyboardShortcut("s")
                .disabled(workspace?.activeTabHasUnsavedChanges != true)
            Button("Save All") { workspace?.saveAll() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(workspace?.hasUnsavedChanges != true)
            Divider()
            Button("Compare with Saved Version") { show(workspace?.comparisonWithSavedVersion()) }
                .disabled(workspace?.activeTabHasUnsavedChanges != true)
            Button("Compare with Last Commit") { compareWithLastCommit() }
                .disabled(workspace?.document == nil || workspace?.isInGitRepository != true)
            Divider()
            Button("Export as HTML…") { workspace.map { MarkdownExportPanel.export(.html, from: $0) } }
                .disabled(workspace?.isMarkdownDocument != true)
            Button("Export as PDF…") { workspace.map { MarkdownExportPanel.export(.pdf, from: $0) } }
                .disabled(workspace?.isMarkdownDocument != true)
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
    /// Does nothing while the scratchpad is showing.
    private func close() {
        guard workspace?.isScratchpadActive != true else { return }
        if let workspace, workspace.document != nil {
            workspace.closeActiveTab()
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }

    private func compareWithLastCommit() {
        guard let workspace else { return }
        Task {
            do throws(AppError) {
                show(try await workspace.comparisonWithLastCommit())
            } catch {
                workspace.presentedError = error
            }
        }
    }

    /// Opens the Compare window with the two versions.
    private func show(_ request: ComparisonRequest?) {
        guard let request else { return }
        compare.show(request)
        openWindow(id: CompareView.windowID)
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
        .disabled(workspace == nil || workspace?.isScratchpadActive == true)
        Divider()
        scratchpadItems
        Divider()
        Button("Show Next Tab") { workspace?.activateNextTab() }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled((workspace?.tabs.count ?? 0) < 2)
        Button("Show Previous Tab") { workspace?.activatePreviousTab() }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled((workspace?.tabs.count ?? 0) < 2)
        Divider()
        Toggle("Wrap Lines", isOn: $wrapsLines)
            .keyboardShortcut("l", modifiers: [.command, .option])
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

    @ViewBuilder
    private var scratchpadItems: some View {
        let isShowing = workspace?.isScratchpadActive == true
        Button(isShowing ? "Hide Scratchpad" : "Show Scratchpad") { workspace?.toggleScratchpad() }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(workspace == nil || (isShowing && workspace?.tabs.isEmpty == true))
        Button("Copy Scratchpad") { workspace?.copyScratchpad() }
            .keyboardShortcut("c", modifiers: [.command, .option, .shift])
            .disabled(workspace?.scratchpadText.isEmpty != false)
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
        Button("Convert to YAML") { workspace?.convertToYAML() }
            .disabled(workspace?.canConvertFromJSON != true)
        Button("Convert to CSV") { workspace?.convertToCSV() }
            .disabled(workspace?.canConvertFromJSON != true)
        Button("Convert to JSON") { workspace?.convertToJSON(indentation: indentation.indentation) }
            .disabled(workspace?.canConvertToJSON != true)
        Divider()
        Button("Generate Swift Model…") { workspace?.showSwiftModelGenerator() }
            .disabled(workspace?.canGenerateSwiftModel != true)
        Divider()
        Button("Compare…") { openWindow(id: CompareView.windowID) }
            .keyboardShortcut("c", modifiers: [.command, .option])
    }
}
