//
//  ScratchpadState.swift
//  LF-Paper
//

import AppKit
import Observation

/// Throwaway text that is never saved, restored or counted as unsaved changes.
/// The workspace decides when it shows; this holds only its own state.
@Observable
final class ScratchpadState {
    /// Whether the scratchpad is showing instead of the active file tab.
    var isActive = false
    private(set) var text = ""
    /// Changes on every copy, so the bar can confirm it.
    private(set) var copyID: UUID?
    /// The editor identity, stable so the scratchpad keeps its own undo history.
    let id = UUID()

    func update(_ text: String) {
        self.text = text
    }

    /// Empties the scratchpad; the editor applies it as an ordinary edit, so Undo brings the text back.
    func clear() {
        text = ""
    }

    func copy(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copyID = UUID()
    }
}
