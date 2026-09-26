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

    /// Quits right away when nothing is unsaved; otherwise acts on the answer from `ask`.
    static func terminateReply(
        for unsaved: [WorkspaceModel],
        ask: ([WorkspaceModel]) -> WorkspaceModel.UnsavedChangesDecision
    ) -> NSApplication.TerminateReply {
        guard !unsaved.isEmpty else { return .terminateNow }

        switch ask(unsaved) {
        case .save:
            // Stops at the first failed save; that window shows the error and the app stays open.
            return unsaved.allSatisfy { $0.saveAll() } ? .terminateNow : .terminateCancel
        case .discard:
            unsaved.forEach { $0.discardUnsavedChanges() }
            return .terminateNow
        case .cancel:
            return .terminateCancel
        }
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
