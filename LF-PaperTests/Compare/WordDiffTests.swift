//
//  WordDiffTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

struct WordDiffTests {
    private func changedText(_ ranges: [NSRange], in text: String) -> [String] {
        ranges.map { (text as NSString).substring(with: $0) }
    }

    @Test func anInsertedCommaIsTheOnlyChange() throws {
        let old = #"    "math""#
        let new = #"    "math","#

        let changes = try #require(WordDiff.changes(from: old, to: new))

        #expect(changes.old.isEmpty)
        #expect(changedText(changes.new, in: new) == [","])
    }

    @Test func aChangedWordIsMarkedOnBothSides() throws {
        let old = #"  "name": "Ada","#
        let new = #"  "name": "Grace","#

        let changes = try #require(WordDiff.changes(from: old, to: new))

        #expect(changedText(changes.old, in: old) == ["Ada"])
        #expect(changedText(changes.new, in: new) == ["Grace"])
    }

    @Test func neighbouringChangesBecomeOneRange() throws {
        let old = "value: 1.5 units"
        let new = "value: 2.75 units"

        let changes = try #require(WordDiff.changes(from: old, to: new))

        #expect(changedText(changes.old, in: old) == ["1.5"])
        #expect(changedText(changes.new, in: new) == ["2.75"])
    }

    @Test func linesWithLittleInCommonAreMarkedWhole() {
        #expect(WordDiff.changes(from: "completely different words", to: "nothing shared at all") == nil)
        #expect(WordDiff.changes(from: "", to: "something") == nil)
    }

    @Test func rangesAreUTF16AndRespectEmoji() throws {
        let old = "café 😀 yes"
        let new = "café 😀 no"

        let changes = try #require(WordDiff.changes(from: old, to: new))

        #expect(changes.new == [NSRange(location: 8, length: 2)])
        #expect(changedText(changes.old, in: old) == ["yes"])
    }

    @Test func identicalLinesHaveNoChanges() throws {
        let changes = try #require(WordDiff.changes(from: "same line", to: "same line"))

        #expect(changes.old.isEmpty)
        #expect(changes.new.isEmpty)
    }

    @Test func pairedRowsCarryTheirWordChanges() throws {
        let lines = TextDiff.lines(from: "{\n  \"a\": 1\n}", to: "{\n  \"a\": 2\n}")

        let rows = SideBySideRows.make(from: lines)
        let changed = try #require(rows.first { $0.isChange })

        #expect(changed.left?.changedRanges == [NSRange(location: 7, length: 1)])
        #expect(changed.right?.changedRanges == [NSRange(location: 7, length: 1)])
        #expect(rows.first?.left?.changedRanges == nil) // unchanged lines have none
    }
}
