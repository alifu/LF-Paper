//
//  WorkspaceModel+TabSession.swift
//  LF-Paper
//

import Foundation
import os

/// Remembering each folder's tabs and selections, and reopening them with the folder.
extension WorkspaceModel {
    /// The editor reports each tab's selection, so it can be restored when the folder reopens.
    func noteSelection(_ range: NSRange, in documentID: UUID) {
        selectionMemory = selectionMemory.noting(range, in: documentID)
    }

    /// Remembers the folder's tabs, active tab and selections. Also called when the window closes
    /// and the app quits, because selection changes alone don't save.
    func saveTabSession() {
        guard let rootURL else { return }
        tabSessions.save(TabSession.make(from: openTabs, root: rootURL, selections: selectionMemory.selections), for: rootURL)
    }

    /// Reopens the folder's remembered tabs; files that are gone are skipped.
    func restoreTabSession(for folder: URL) {
        guard let session = tabSessions.session(for: folder) else { return }
        let (restored, pendingSelections) = session.restore(in: folder, reading: readRestoredFile)
        selectionMemory = TabSelectionMemory(pending: pendingSelections)
        openTabs = restored
        syncSelectionWithActiveTab()
        revealPendingSelection()
    }

    /// Puts back the remembered selection of the active tab the first time it shows.
    func revealPendingSelection() {
        guard let document else { return }
        let (range, remaining) = selectionMemory.takingPending(for: document.id)
        selectionMemory = remaining
        guard let range else { return }
        reveal(range, focusesEditor: false, highlights: false)
    }

    private func readRestoredFile(_ url: URL) -> String? {
        guard fileService.exists(url) else { return nil }
        do throws(AppError) {
            return try fileService.read(url)
        } catch {
            Self.logger.error("Could not reopen a tab: \(String(describing: error))")
            return nil
        }
    }
}
