//
//  SwiftHighlighterTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

/// Simple Swift highlighting for `.swift` files: keywords, attributes, strings, numbers and line comments.
struct SwiftHighlighterTests {
    private struct Run: Equatable, CustomStringConvertible {
        let kind: TokenKind
        let text: String
        var description: String { "\(kind): \(text.debugDescription)" }
    }

    /// The colored runs after later tokens paint over earlier ones.
    private func runs(in source: String) -> [Run] {
        let text = source as NSString
        var kinds = [TokenKind?](repeating: nil, count: text.length)
        for token in SwiftHighlighter().tokens(in: text, range: NSRange(location: 0, length: text.length)) {
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

    @Test func declarationsAndTypes() {
        #expect(runs(in: "public struct User: Codable {\n    let id: Int\n}") == [
            Run(kind: .keyword, text: "public"),
            Run(kind: .keyword, text: "struct"),
            Run(kind: .keyword, text: "let"),
        ])
    }

    @Test func stringsNumbersAndLiterals() {
        #expect(runs(in: #"case name = "first_name", 42, 1.5e3, 0xFF, true, nil"#) == [
            Run(kind: .keyword, text: "case"),
            Run(kind: .string, text: #""first_name""#),
            Run(kind: .number, text: "42"),
            Run(kind: .number, text: "1.5e3"),
            Run(kind: .number, text: "0xFF"),
            Run(kind: .literal, text: "true"),
            Run(kind: .literal, text: "nil"),
        ])
    }

    @Test func escapedQuotesStayInTheString() {
        #expect(runs(in: #"let s = "a \"quoted\" word""#) == [
            Run(kind: .keyword, text: "let"),
            Run(kind: .string, text: #""a \"quoted\" word""#),
        ])
    }

    @Test func lineCommentsButNotSlashesInStrings() {
        #expect(runs(in: "let url = \"https://a.com\" // the site\n// whole line") == [
            Run(kind: .keyword, text: "let"),
            Run(kind: .string, text: #""https://a.com""#),
            Run(kind: .comment, text: "// the site"),
            Run(kind: .comment, text: "// whole line"),
        ])
    }

    @Test func keywordsInsideCommentsAndStringsArentKeywords() {
        #expect(runs(in: "// let x\n\"struct\"") == [
            Run(kind: .comment, text: "// let x"),
            Run(kind: .string, text: #""struct""#),
        ])
    }

    @Test func attributesAndBackticks() {
        #expect(runs(in: "@MainActor let `default`: String") == [
            Run(kind: .key, text: "@MainActor"),
            Run(kind: .keyword, text: "let"),
        ])
    }

    @Test func numbersInsideNamesArentNumbers() {
        #expect(runs(in: "let item2 = _2fa") == [Run(kind: .keyword, text: "let")])
    }
}
