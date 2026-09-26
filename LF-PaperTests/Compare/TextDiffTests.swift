//
//  TextDiffTests.swift
//  LF-PaperTests
//

import Testing
@testable import LF_Paper

struct TextDiffTests {
    /// " text" for unchanged lines, "-text" removed, "+text" added.
    private func marked(_ old: String, _ new: String) -> [String] {
        TextDiff.lines(from: old, to: new).map { line in
            switch line.kind {
            case .same: " \(line.text)"
            case .removed: "-\(line.text)"
            case .added: "+\(line.text)"
            }
        }
    }

    @Test func identicalTextIsAllUnchanged() {
        #expect(marked("a\nb", "a\nb") == [" a", " b"])
    }

    @Test func aChangedLineIsARemovalThenAnAddition() {
        #expect(marked("a\nb\nc", "a\nx\nc") == [" a", "-b", "+x", " c"])
    }

    @Test func insertionsAndDeletionsAtTheEnds() {
        #expect(marked("a\nb", "z\na\nb\nc") == ["+z", " a", " b", "+c"])
        #expect(marked("a\nb\nc", "b") == ["-a", " b", "-c"])
    }

    @Test func aFinalNewlineIsNotALine() {
        #expect(marked("a\n", "a") == [" a"])
    }

    @Test func emptyTextHasNoLines() {
        #expect(marked("", "a") == ["+a"])
    }

    @Test func linesCarryTheirNumbersOnEachSide() {
        let lines = TextDiff.lines(from: "a\nb\nc", to: "a\nx\nc")

        #expect(lines.map(\.oldLineNumber) == [1, 2, nil, 3])
        #expect(lines.map(\.newLineNumber) == [1, nil, 2, 3])
    }

    // MARK: Side by side

    /// "left | right" for each row, with "·" for an empty side.
    private func rows(_ old: String, _ new: String) -> [String] {
        SideBySideRows.make(from: TextDiff.lines(from: old, to: new)).map { row in
            "\(row.left?.text ?? "·") | \(row.right?.text ?? "·")"
        }
    }

    @Test func aChangedLineSitsOppositeItsReplacement() {
        #expect(rows("a\nb\nc", "a\nx\nc") == ["a | a", "b | x", "c | c"])
    }

    @Test func unevenChangesLeaveOneSideEmpty() {
        #expect(rows("a\nb\nc\nd", "a\nx\nd") == ["a | a", "b | x", "c | ·", "d | d"])
        #expect(rows("a", "a\nb") == ["a | a", "· | b"])
    }

    @Test func eachBlockOfChangesStartsAChange() {
        let result = SideBySideRows.make(from: TextDiff.lines(from: "a\nb\nc\nd\ne", to: "a\nB\nc\nD\nE"))

        #expect(result.map(\.isChange) == [false, true, false, true, true])
        #expect(SideBySideRows.changeStarts(in: result) == [1, 3])
    }
}
