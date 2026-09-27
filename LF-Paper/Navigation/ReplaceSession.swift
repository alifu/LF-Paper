//
//  ReplaceSession.swift
//  LF-Paper
//

import Foundation
import Observation

/// What Replace All did, for the message under the search field.
nonisolated struct ReplaceOutcome: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case replaced(count: Int)
        case undone
    }

    let action: Action
    let fileCount: Int
    let skipped: [SkippedFile]

    /// "Replaced 4 matches in 3 files." or "Put back the original text of 2 files."
    var message: String {
        let files = "\(fileCount) \(fileCount == 1 ? "file" : "files")"
        switch action {
        case .replaced(let count):
            return "Replaced \(count) \(count == 1 ? "match" : "matches") in \(files)."
        case .undone:
            return "Put back the original text of \(files)."
        }
    }
}

/// The state of Replace All for one window: the replacement text, the preview being reviewed,
/// the files left out of it, and what the last replace wrote to disk (for Undo Replace All).
@Observable
final class ReplaceSession {
    var replacement = ""
    /// Whether the Replace field shows under the search field.
    var isReplaceShown = false
    /// Changes whenever the Replace field should take keyboard focus.
    private(set) var focusRequest: UUID?
    /// The preview waiting for Replace or Cancel.
    private(set) var plan: ReplacePlan?
    /// Files in the preview the user left out.
    private(set) var excludedFiles: Set<URL> = []
    private(set) var isPreparing = false
    private(set) var error: ReplaceError?
    private(set) var outcome: ReplaceOutcome?
    /// Files the last Replace All wrote to disk, with their text before and after.
    private(set) var undoRecord: [FileReplacement] = []
    /// The preview being worked out; tests await it.
    @ObservationIgnored private(set) var task: Task<Void, Never>?
    /// Only the latest preview may finish; an earlier one can still be running.
    @ObservationIgnored private var currentPreparationID: UUID?

    var canUndo: Bool { !undoRecord.isEmpty }

    /// Shows the Replace field and moves keyboard focus into it.
    func show() {
        isReplaceShown = true
        focusRequest = UUID()
    }

    /// Works out a new preview (off the main thread, in `build`), replacing any open one.
    func prepare(_ build: @escaping @MainActor () async -> Result<ReplacePlan, ReplaceError>) {
        cancel()
        error = nil
        outcome = nil
        excludedFiles = []
        isPreparing = true
        let id = UUID()
        currentPreparationID = id
        task = Task { [weak self] in
            let result = await build()
            guard let self, self.currentPreparationID == id else { return }
            self.isPreparing = false
            switch result {
            case .success(let plan): self.plan = plan
            case .failure(let error): self.error = error
            }
        }
    }

    func isIncluded(_ file: URL) -> Bool {
        !excludedFiles.contains(file)
    }

    func setIncluded(_ isIncluded: Bool, _ file: URL) {
        excludedFiles = isIncluded ? excludedFiles.subtracting([file]) : excludedFiles.union([file])
    }

    /// Closes the preview without replacing anything.
    func cancel() {
        task?.cancel()
        currentPreparationID = nil
        isPreparing = false
        plan = nil
    }

    /// The preview was applied; `written` can be undone once, until the next replace.
    func didReplace(_ outcome: ReplaceOutcome, written: [FileReplacement]) {
        plan = nil
        self.outcome = outcome
        undoRecord = written
    }

    /// Hands over what Undo Replace All should put back; it can only be undone once.
    func takeUndoRecord() -> [FileReplacement] {
        let record = undoRecord
        undoRecord = []
        return record
    }

    func didUndo(_ outcome: ReplaceOutcome) {
        self.outcome = outcome
    }

    /// Forgets everything but the replacement text, for example when another folder opens.
    func reset() {
        cancel()
        error = nil
        outcome = nil
        excludedFiles = []
        undoRecord = []
    }
}
