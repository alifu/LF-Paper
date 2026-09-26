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
        CommandGroup(after: .sidebar) {
            Toggle("Show Hidden Files", isOn: showsHiddenFiles)
                .keyboardShortcut(".", modifiers: [.command, .shift])
                .disabled(workspace == nil)
        }
    }

    private var showsHiddenFiles: Binding<Bool> {
        Binding(
            get: { workspace?.showsHiddenFiles ?? false },
            set: { workspace?.showsHiddenFiles = $0 }
        )
    }
}
