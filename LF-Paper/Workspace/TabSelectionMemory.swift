//
//  TabSelectionMemory.swift
//  LF-Paper
//

import Foundation

/// The editor selection of each open tab, remembered for the tab session.
/// Immutable: every change returns a new value.
nonisolated struct TabSelectionMemory: Equatable, Sendable {
    static let empty = TabSelectionMemory()

    /// The latest selection the editor reported for each tab.
    private let noted: [UUID: NSRange]
    /// Remembered selections of restored tabs, put back when each tab is first shown.
    private let pending: [UUID: NSRange]

    init(pending: [UUID: NSRange] = [:]) {
        self.init(noted: [:], pending: pending)
    }

    private init(noted: [UUID: NSRange], pending: [UUID: NSRange]) {
        self.noted = noted
        self.pending = pending
    }

    /// What to remember for each tab: its reported selection, or else the one still waiting to be put back.
    var selections: [UUID: NSRange] {
        pending.merging(noted) { _, reported in reported }
    }

    /// The editor reported a selection, so a pending one is no longer needed.
    func noting(_ range: NSRange, in id: UUID) -> TabSelectionMemory {
        var reported = noted
        reported[id] = range
        var waiting = pending
        waiting[id] = nil
        return TabSelectionMemory(noted: reported, pending: waiting)
    }

    /// The tab's pending selection, if any, and the memory without it.
    func takingPending(for id: UUID) -> (range: NSRange?, memory: TabSelectionMemory) {
        guard let range = pending[id] else { return (nil, self) }
        var waiting = pending
        waiting[id] = nil
        return (range, TabSelectionMemory(noted: noted, pending: waiting))
    }
}
