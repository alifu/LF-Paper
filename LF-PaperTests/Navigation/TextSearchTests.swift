//
//  TextSearchTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

struct TextSearchTests {
    private func matches(
        _ pattern: String,
        in text: String,
        matchesCase: Bool = false,
        wholeWord: Bool = false,
        regex: Bool = false,
        limit: Int = 100
    ) throws -> [TextMatch] {
        let options = SearchOptions(matchesCase: matchesCase, matchesWholeWord: wholeWord, usesRegularExpression: regex)
        let expression = try SearchQuery(text: pattern, options: options).regularExpression()
        return TextSearch.matches(of: expression, in: text, limit: limit)
    }

    private func matchedText(_ matches: [TextMatch], in text: String) -> [String] {
        matches.map { (text as NSString).substring(with: $0.range) }
    }

    @Test func ignoresCaseByDefault() throws {
        let text = "Title\ntitle\nTITLE"

        #expect(try matches("title", in: text).count == 3)
        #expect(try matchedText(matches("title", in: text, matchesCase: true), in: text) == ["title"])
    }

    @Test func wholeWordSkipsPartsOfWords() throws {
        let text = "cat catalog concat cat."

        #expect(try matches("cat", in: text).count == 4)
        #expect(try matches("cat", in: text, wholeWord: true).map(\.range.location) == [0, 19])
    }

    @Test func plainTextSearchTreatsRegexCharactersLiterally() throws {
        let text = "a.b axb (a.b)"

        #expect(try matchedText(matches("a.b", in: text), in: text) == ["a.b", "a.b"])
        #expect(try matchedText(matches("a.b", in: text, regex: true), in: text) == ["a.b", "axb", "a.b"])
    }

    @Test func regularExpressionsCanUseGroupsAndClasses() throws {
        let text = #"{"id": 12, "name": "x", "id": 345}"#

        #expect(try matchedText(matches(#""id": \d+"#, in: text, regex: true), in: text) == [#""id": 12"#, #""id": 345"#])
    }

    @Test func anInvalidPatternIsReported() {
        #expect(throws: SearchQueryError.self) {
            _ = try SearchQuery(text: "(unclosed", options: SearchOptions(usesRegularExpression: true)).regularExpression()
        }
        #expect(throws: SearchQueryError.emptyQuery) {
            _ = try SearchQuery(text: "", options: SearchOptions()).regularExpression()
        }
    }

    @Test func emptyMatchesAreSkipped() throws {
        #expect(try matches("x*", in: "abc", regex: true).isEmpty)
    }

    @Test func reportsLineNumbersAndTheLineAroundTheMatch() throws {
        let text = "# Title\n\n    Find the needle here\nlast"

        let match = try #require(try matches("needle", in: text).first)

        #expect(match.lineNumber == 3)
        #expect(match.preview == "Find the needle here")
        #expect((match.preview as NSString).substring(with: match.previewRange) == "needle")
    }

    @Test func longLinesAreShortenedAroundTheMatch() throws {
        let text = String(repeating: "a", count: 500) + "needle" + String(repeating: "b", count: 500)

        let match = try #require(try matches("needle", in: text).first)

        #expect(match.preview.count < 250)
        #expect(match.preview.hasPrefix("…"))
        #expect(match.preview.hasSuffix("…"))
        #expect((match.preview as NSString).substring(with: match.previewRange) == "needle")
    }

    @Test func rangesAreUTF16ForTheEditor() throws {
        let text = "😀 needle"

        let match = try #require(try matches("needle", in: text).first)

        #expect(match.range == NSRange(location: 3, length: 6))
    }

    @Test func stopsAtTheLimit() throws {
        #expect(try matches("a", in: String(repeating: "a", count: 50), limit: 10).count == 10)
    }
}
