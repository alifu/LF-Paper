//
//  JSONHighlighterTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

struct JSONHighlighterTests {
    /// A run of text and the kind it ends up colored as, after later tokens paint over earlier ones.
    private struct Run: Equatable, CustomStringConvertible {
        let kind: TokenKind
        let text: String
        var description: String { "\(kind): \(text.debugDescription)" }
    }

    private func runs(in json: String) -> [Run] {
        let text = json as NSString
        var kinds = [TokenKind?](repeating: nil, count: text.length)
        for token in JSONHighlighter().tokens(in: text, range: NSRange(location: 0, length: text.length)) {
            for index in token.range.location..<NSMaxRange(token.range) {
                kinds[index] = token.kind
            }
        }
        var result: [Run] = []
        var start = 0
        while start < kinds.count {
            var end = start + 1
            while end < kinds.count, kinds[end] == kinds[start] { end += 1 }
            if let kind = kinds[start] {
                result.append(Run(kind: kind, text: text.substring(with: NSRange(location: start, length: end - start))))
            }
            start = end
        }
        return result
    }

    @Test func colorsKeysStringsNumbersLiteralsAndPunctuation() {
        #expect(runs(in: #"{"a": "x1", "n": -2.5e3, "t": true, "z": null}"#) == [
            Run(kind: .punctuation, text: "{"),
            Run(kind: .key, text: #""a""#),
            Run(kind: .punctuation, text: ":"),
            Run(kind: .string, text: #""x1""#),
            Run(kind: .punctuation, text: ","),
            Run(kind: .key, text: #""n""#),
            Run(kind: .punctuation, text: ":"),
            Run(kind: .number, text: "-2.5e3"),
            Run(kind: .punctuation, text: ","),
            Run(kind: .key, text: #""t""#),
            Run(kind: .punctuation, text: ":"),
            Run(kind: .literal, text: "true"),
            Run(kind: .punctuation, text: ","),
            Run(kind: .key, text: #""z""#),
            Run(kind: .punctuation, text: ":"),
            Run(kind: .literal, text: "null"),
            Run(kind: .punctuation, text: "}"),
        ])
    }

    @Test func stringsWithEscapedQuotesAndLookalikesStayStrings() {
        #expect(runs(in: #"["say \"hi\": 42, true"]"#) == [
            Run(kind: .punctuation, text: "["),
            Run(kind: .string, text: #""say \"hi\": 42, true""#),
            Run(kind: .punctuation, text: "]"),
        ])
    }

    @Test func keysMayHaveSpaceBeforeTheColon() {
        #expect(runs(in: #"{"k" : 1}"#).first { $0.kind == .key } == Run(kind: .key, text: #""k""#))
    }

    @Test func stringValuesAreNotKeys() {
        #expect(!runs(in: #"["a", "b"]"#).contains { $0.kind == .key })
    }
}
