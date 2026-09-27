//
//  WorkspaceModel+Scratchpad.swift
//  LF-Paper
//

import AppKit

/// The scratchpad tab: showing it in place of the file tabs, and its text.
extension WorkspaceModel {
    /// Whether the scratchpad is showing instead of the active file tab.
    var isScratchpadActive: Bool { scratchpad.isActive }

    /// Throwaway text that is never saved, restored or counted as unsaved changes.
    var scratchpadText: String { scratchpad.text }

    /// Changes on every copy of the scratchpad, so the bar can confirm it.
    var scratchpadCopyID: UUID? { scratchpad.copyID }

    /// The scratchpad's editor identity, stable so it keeps its own undo history.
    var scratchpadID: UUID { scratchpad.id }

    func showScratchpad() {
        setScratchpadActive(true)
        syncSelectionWithActiveTab()
    }

    /// Shows the scratchpad, or goes back to the last file tab when it's already showing.
    func toggleScratchpad() {
        guard isScratchpadActive else {
            showScratchpad()
            return
        }
        guard let lastTab = openTabs.active else { return }
        activateTab(lastTab.id)
    }

    func updateScratchpadText(_ text: String) {
        scratchpad.update(text)
    }

    /// Empties the scratchpad; the editor applies it as an ordinary edit, so Undo brings the text back.
    func clearScratchpad() {
        scratchpad.clear()
    }

    func copyScratchpad(to pasteboard: NSPasteboard = .general) {
        scratchpad.copy(to: pasteboard)
    }
}
