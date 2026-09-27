//
//  AutosaveScheduler.swift
//  LF-Paper
//

import Foundation

/// Saves edited tabs once typing has paused: every edit restarts the countdown.
final class AutosaveScheduler {
    /// How long to wait after typing stops; `nil` turns autosave off.
    var delay: Duration?
    /// The pending save; tests await it.
    private(set) var task: Task<Void, Never>?

    /// Runs `save` once `delay` passes without another call. Cancels the previous countdown.
    func schedule(_ save: @escaping @MainActor () -> Void) {
        task?.cancel()
        guard let delay else {
            task = nil
            return
        }
        task = Task {
            try? await Task.sleep(for: delay) // a cancelled sleep ends early; checked below
            guard !Task.isCancelled else { return }
            save()
        }
    }

    /// The tabs autosave may write: edited files that exist on disk. Files deleted on disk or
    /// never saved are only written by an explicit Save.
    nonisolated static func documentsToSave(in tabs: DocumentTabs) -> [UUID] {
        tabs.documents
            .filter { $0.isDirty && !$0.isNew && !tabs.missingOnDisk.contains($0.id) }
            .map(\.id)
    }
}
