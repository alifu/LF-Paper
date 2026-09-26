//
//  AppDelegate.swift
//  LF-Paper
//

import AppKit

/// Asks about unsaved changes before the app quits.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.terminateReply(for: WorkspaceRegistry.shared.workspacesWithUnsavedChanges, ask: askToSave)
    }

    /// Remembers every window's open tabs (with their latest selections) for the next launch.
    func applicationWillTerminate(_ notification: Notification) {
        WorkspaceRegistry.shared.workspaces.forEach { $0.saveTabSession() }
    }

    /// Quits right away when nothing is unsaved; otherwise acts on the answer from `ask`.
    static func terminateReply(
        for unsaved: [WorkspaceModel],
        ask: ([WorkspaceModel]) -> WorkspaceModel.UnsavedChangesDecision
    ) -> NSApplication.TerminateReply {
        guard !unsaved.isEmpty else { return .terminateNow }
        return ask(unsaved).apply(to: unsaved) ? .terminateNow : .terminateCancel
    }

    private func askToSave(_ workspaces: [WorkspaceModel]) -> WorkspaceModel.UnsavedChangesDecision {
        let alert = NSAlert()
        alert.messageText = UnsavedChangesPrompt.message(for: workspaces.flatMap(\.unsavedDocuments))
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
