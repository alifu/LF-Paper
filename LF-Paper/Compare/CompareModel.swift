//
//  CompareModel.swift
//  LF-Paper
//

import Foundation
import Observation

/// State of the Compare window: the two sides, the options, the latest comparison and which
/// change is focused. Re-compares in the background whenever something changes.
@Observable
final class CompareModel {
    struct Side: Equatable, Sendable {
        let title: String
        let text: String
    }

    /// Pause before comparing, so typing an array key doesn't compare on every keystroke.
    private static let comparisonDelay: Duration = .milliseconds(200)

    private(set) var left: Side?
    private(set) var right: Side?
    var ignoresKeyOrder = true {
        didSet {
            if ignoresKeyOrder != oldValue { scheduleComparison() }
        }
    }
    /// Blank means "compare arrays by position".
    var arrayMatchKey = "" {
        didSet {
            if arrayMatchKey != oldValue { scheduleComparison() }
        }
    }
    private(set) var outcome: JSONComparison.Outcome = .incomplete
    /// Index into the result's change blocks.
    private(set) var focusedChange: Int?
    var presentedError: AppError?

    /// The running comparison; tests await it.
    @ObservationIgnored private(set) var comparisonTask: Task<Void, Never>?

    var result: JSONComparison.Result? {
        guard case .compared(let result) = outcome else { return nil }
        return result
    }

    var changeCount: Int {
        result?.changeStarts.count ?? 0
    }

    // MARK: Sides

    func setSide(_ side: JSONComparison.Side, title: String, text: String) {
        let value = Side(title: title, text: text)
        switch side {
        case .left: left = value
        case .right: right = value
        }
        scheduleComparison()
    }

    func clearSide(_ side: JSONComparison.Side) {
        switch side {
        case .left: left = nil
        case .right: right = nil
        }
        scheduleComparison()
    }

    func swapSides() {
        (left, right) = (right, left)
        scheduleComparison()
    }

    /// Reads a file chosen by the user (security-scoped when it came from an Open panel).
    func loadSide(_ side: JSONComparison.Side, from url: URL) {
        let access = SecurityScopedAccess(url: url)
        defer { withExtendedLifetime(access) {} }
        do throws(AppError) {
            let text = try LocalFileService().read(url)
            setSide(side, title: url.lastPathComponent, text: text)
        } catch {
            presentedError = error
        }
    }

    // MARK: Navigation

    func focusNextChange() {
        guard changeCount > 0 else { return }
        focusedChange = focusedChange.map { ($0 + 1) % changeCount } ?? 0
    }

    func focusPreviousChange() {
        guard changeCount > 0 else { return }
        focusedChange = focusedChange.map { ($0 - 1 + changeCount) % changeCount } ?? changeCount - 1
    }

    // MARK: Comparing

    private func scheduleComparison() {
        comparisonTask?.cancel()
        let leftText = left?.text
        let rightText = right?.text
        let key = arrayMatchKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let options = JSONComparison.Options(ignoresKeyOrder: ignoresKeyOrder, arrayMatchKey: key.isEmpty ? nil : key)
        comparisonTask = Task { [weak self] in
            try? await Task.sleep(for: Self.comparisonDelay) // cancelled sleeps end early; checked below
            guard !Task.isCancelled else { return }
            let outcome = await JSONComparison.runInBackground(left: leftText, right: rightText, options: options)
            guard !Task.isCancelled else { return }
            self?.apply(outcome)
        }
    }

    private func apply(_ outcome: JSONComparison.Outcome) {
        self.outcome = outcome
        focusedChange = nil
    }
}
