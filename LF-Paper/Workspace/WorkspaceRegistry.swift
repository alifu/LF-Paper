//
//  WorkspaceRegistry.swift
//  LF-Paper
//

import Foundation

/// Keeps track of open workspace windows so the app can check for unsaved changes before quitting.
/// Holds them weakly: a closed window's workspace simply drops out.
final class WorkspaceRegistry {
    static let shared = WorkspaceRegistry()

    private var entries: [WeakWorkspace] = []

    func register(_ workspace: WorkspaceModel) {
        let others = entries.filter { $0.workspace != nil && $0.workspace !== workspace }
        entries = others + [WeakWorkspace(workspace: workspace)]
    }

    var workspacesWithUnsavedChanges: [WorkspaceModel] {
        entries.compactMap(\.workspace).filter(\.hasUnsavedChanges)
    }
}

private struct WeakWorkspace {
    weak var workspace: WorkspaceModel?
}
