//
//  AppDelegate.swift
//  LF-Paper
//

import AppKit

/// Asks about unsaved changes before the app quits.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let unsaved = WorkspaceRegistry.shared.workspacesWithUnsavedChanges
        guard !unsaved.isEmpty else { return .terminateNow }

        switch askToSave(unsaved) {
        case .save:
            // Stops at the first failed save; that window shows the error and the app stays open.
            return unsaved.allSatisfy { $0.save() } ? .terminateNow : .terminateCancel
        case .discard:
            unsaved.forEach { $0.discardUnsavedChanges() }
            return .terminateNow
        case .cancel:
            return .terminateCancel
        }
    }

    private func askToSave(_ workspaces: [WorkspaceModel]) -> WorkspaceModel.UnsavedChangesDecision {
        let alert = NSAlert()
        if workspaces.count == 1, let name = workspaces.first?.document?.url.lastPathComponent {
            alert.messageText = UnsavedChangesPrompt.message(fileName: name)
        } else {
            alert.messageText = UnsavedChangesPrompt.message(windowCount: workspaces.count)
        }
        alert.informativeText = UnsavedChangesPrompt.informativeText
        alert.addButton(withTitle: UnsavedChangesPrompt.saveTitle)
        alert.addButton(withTitle: UnsavedChangesPrompt.discardTitle)
        alert.addButton(withTitle: UnsavedChangesPrompt.cancelTitle)

        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertSecondButtonReturn: return .discard
        default: return .cancel
        }
    }
}
