//
//  RegexHighlighterTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

struct RegexHighlighterTests {
    private let highlighter = RegexHighlighter(rules: [
        .init(.number, pattern: #"\d+"#),
        .init(.key, pattern: #"^(\w+):"#, captureGroup: 1),
    ])

    private func fullRange(of text: NSString) -> NSRange {
        NSRange(location: 0, length: text.length)
    }

    @Test func findsTokensWithTheirRangesInRuleOrder() {
        let text = "age: 42" as NSString

        let tokens = highlighter.tokens(in: text, range: fullRange(of: text))

        #expect(tokens == [
            SyntaxToken(kind: .number, range: NSRange(location: 5, length: 2)),
            SyntaxToken(kind: .key, range: NSRange(location: 0, length: 3)),
        ])
    }

    @Test func onlyReturnsTokensInsideTheRequestedRange() {
        let text = "1\n2\n3" as NSString

        let tokens = highlighter.tokens(in: text, range: NSRange(location: 2, length: 1))

        #expect(tokens == [SyntaxToken(kind: .number, range: NSRange(location: 2, length: 1))])
    }

    @Test func skipsCaptureGroupsThatDidNotParticipate() {
        let optionalGroup = RegexHighlighter(rules: [.init(.string, pattern: "(a)|b", captureGroup: 1)])
        let text = "b" as NSString

        #expect(optionalGroup.tokens(in: text, range: fullRange(of: text)).isEmpty)
    }

    @Test func invalidationRangeCoversTheWholeEditedLine() {
        let text = "one\ntwo\nthree" as NSString

        let range = highlighter.invalidationRange(for: NSRange(location: 5, length: 1), in: text)

        #expect(range == NSRange(location: 4, length: 4)) // "two\n"
    }

    @Test func invalidationRangeSpansEveryLineTouchedByTheEdit() {
        let text = "one\ntwo\nthree" as NSString

        let range = highlighter.invalidationRange(for: NSRange(location: 2, length: 4), in: text)

        #expect(range == NSRange(location: 0, length: 8)) // "one\ntwo\n"
    }

    @Test func invalidationRangeClampsEditsPastTheEnd() {
        let text = "one\ntwo" as NSString

        let range = highlighter.invalidationRange(for: NSRange(location: 50, length: 3), in: text)

        #expect(range == NSRange(location: 4, length: 3)) // "two"
    }
}
