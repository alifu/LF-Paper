//
//  WorkspaceCommands.swift
//  LF-Paper
//

import SwiftUI

extension FocusedValues {
    /// The workspace of the key window, for menu commands.
    @Entry var workspace: WorkspaceModel?
}

/// File and View menu commands that act on the key window's workspace.
struct WorkspaceCommands: Commands {
    @FocusedValue(\.workspace) private var workspace

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Folder…") { workspace?.isFolderPickerPresented = true }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(workspace == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { _ = workspace?.save() }
                .keyboardShortcut("s")
                .disabled(workspace?.hasUnsavedChanges != true)
        }
        CommandGroup(after: .sidebar) {
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
        }
        CommandMenu("JSON") {
            Group {
                Button("Format") { workspace?.formatJSON() }
                    .keyboardShortcut("f", modifiers: [.option, .shift])
                Button("Format with Sorted Keys") { workspace?.formatJSON(sortsKeys: true) }
                Button("Minify") { workspace?.minifyJSON() }
            }
            .disabled(workspace?.isJSONDocument != true)
        }
    }

    private var showsHiddenFiles: Binding<Bool> {
        Binding(
            get: { workspace?.showsHiddenFiles ?? false },
            set: { workspace?.showsHiddenFiles = $0 }
        )
    }
}
