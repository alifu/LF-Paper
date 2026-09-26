//
//  TextDiff.swift
//  LF-Paper
//

import Foundation

nonisolated struct TextDiffLine: Equatable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        case same, removed, added
    }

    let kind: Kind
    let text: String
    /// 1-based; `nil` for lines that only exist on the other side.
    let oldLineNumber: Int?
    let newLineNumber: Int?
}

/// Line-by-line difference (Myers, via `CollectionDifference`). A final newline isn't a line.
nonisolated enum TextDiff {
    static func lines(from old: String, to new: String) -> [TextDiffLine] {
        let oldLines = splitLines(old)
        let newLines = splitLines(new)
        var removed: Set<Int> = []
        var inserted: Set<Int> = []
        for change in newLines.difference(from: oldLines) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var result: [TextDiffLine] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < oldLines.count || newIndex < newLines.count {
            if oldIndex < oldLines.count, removed.contains(oldIndex) {
                result.append(TextDiffLine(kind: .removed, text: oldLines[oldIndex], oldLineNumber: oldIndex + 1, newLineNumber: nil))
                oldIndex += 1
            } else if newIndex < newLines.count, inserted.contains(newIndex) {
                result.append(TextDiffLine(kind: .added, text: newLines[newIndex], oldLineNumber: nil, newLineNumber: newIndex + 1))
                newIndex += 1
            } else if oldIndex < oldLines.count, newIndex < newLines.count {
                result.append(TextDiffLine(kind: .same, text: oldLines[oldIndex], oldLineNumber: oldIndex + 1, newLineNumber: newIndex + 1))
                oldIndex += 1
                newIndex += 1
            } else {
                break // unreachable: a difference always accounts for every line on both sides
            }
        }
        return result
    }

    private static func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" {
            lines.removeLast()
        }
        return lines
    }
}

/// One side of a side-by-side row.
nonisolated struct DiffCell: Equatable, Sendable {
    let lineNumber: Int
    let text: String
    let kind: TextDiffLine.Kind
}

/// A row of the side-by-side view: the old line on the left, the new one on the right.
nonisolated struct SideBySideRow: Identifiable, Equatable, Sendable {
    let id: Int
    let left: DiffCell?
    let right: DiffCell?

    var isChange: Bool {
        left?.kind != .same || right?.kind != .same
    }

    /// What VoiceOver reads for the row, since the colors alone carry the meaning.
    var accessibilityDescription: String {
        if let left, left.kind == .same {
            return "Line \(left.lineNumber): \(left.text)"
        }
        return [left, right].compactMap { $0?.accessibilityDescription }.joined(separator: ". ")
    }
}

private extension DiffCell {
    nonisolated var accessibilityDescription: String {
        let change = switch kind {
        case .removed: "Removed line"
        case .added: "Added line"
        case .same: "Line"
        }
        return "\(change) \(lineNumber): \(text)"
    }
}

nonisolated enum SideBySideRows {
    /// Pairs each block of removed lines with the added lines that follow it, row by row.
    static func make(from lines: [TextDiffLine]) -> [SideBySideRow] {
        var rows: [SideBySideRow] = []
        var removed: [TextDiffLine] = []
        var added: [TextDiffLine] = []

        func flushChanges() {
            for index in 0..<max(removed.count, added.count) {
                let left = index < removed.count ? cell(removed[index], number: removed[index].oldLineNumber) : nil
                let right = index < added.count ? cell(added[index], number: added[index].newLineNumber) : nil
                rows.append(SideBySideRow(id: rows.count, left: left, right: right))
            }
            removed = []
            added = []
        }

        for line in lines {
            switch line.kind {
            case .removed:
                removed.append(line)
            case .added:
                added.append(line)
            case .same:
                flushChanges()
                rows.append(SideBySideRow(
                    id: rows.count,
                    left: cell(line, number: line.oldLineNumber),
                    right: cell(line, number: line.newLineNumber)
                ))
            }
        }
        flushChanges()
        return rows
    }

    /// The first row of every run of changed rows.
    static func changeStarts(in rows: [SideBySideRow]) -> [Int] {
        rows.indices.filter { rows[$0].isChange && ($0 == 0 || !rows[$0 - 1].isChange) }
    }

    private static func cell(_ line: TextDiffLine, number: Int?) -> DiffCell {
        DiffCell(lineNumber: number ?? 0, text: line.text, kind: line.kind)
    }
}
