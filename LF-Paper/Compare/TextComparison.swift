//
//  TextComparison.swift
//  LF-Paper
//

import Foundation

/// What the Compare window compares: JSON by structure (formatted alike), or any text line by line.
nonisolated enum CompareContentKind: Equatable, Sendable {
    case json
    case text

    init(fileKind: FileKind?) {
        self = fileKind == .json ? .json : .text
    }
}

/// Two sides to show in the Compare window, such as a file's saved and edited text.
nonisolated struct ComparisonRequest: Equatable, Sendable {
    let left: CompareModel.Side
    let right: CompareModel.Side
    let kind: CompareContentKind
}

/// Compares two texts line by line as written, for Markdown and other non-JSON text.
nonisolated enum TextComparison {
    static func run(left: String?, right: String?) -> JSONComparison.Outcome {
        guard let left, let right else { return .incomplete }
        let rows = SideBySideRows.make(from: TextDiff.lines(from: left, to: right))
        return .compared(JSONComparison.Result(differences: [], rows: rows, changeStarts: SideBySideRows.changeStarts(in: rows)))
    }

    /// Same as `run`, off the main thread.
    @concurrent
    static func runInBackground(left: String?, right: String?) async -> JSONComparison.Outcome {
        run(left: left, right: right)
    }
}
