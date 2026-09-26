//
//  MarkdownHighlighterTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

struct MarkdownHighlighterTests {
    /// A token with the text it covers, so expectations read like the Markdown itself.
    private struct Found: Equatable, CustomStringConvertible {
        let kind: TokenKind
        let text: String
        var description: String { "\(kind): \(text.debugDescription)" }
    }

    private let highlighter = MarkdownHighlighter()

    private func found(in markdown: String, range: NSRange? = nil) -> [Found] {
        let text = markdown as NSString
        let searchRange = range ?? NSRange(location: 0, length: text.length)
        return highlighter.tokens(in: text, range: searchRange)
            .map { Found(kind: $0.kind, text: text.substring(with: $0.range)) }
    }

    // MARK: Block elements

    @Test func headingsNeedASpaceAfterTheHashes() {
        #expect(found(in: "# Title") == [Found(kind: .heading, text: "# Title")])
        #expect(found(in: "### Deeper") == [Found(kind: .heading, text: "### Deeper")])
        #expect(found(in: "#hashtag").isEmpty)
    }

    @Test func blockQuotesCoverTheWholeLine() {
        #expect(found(in: "> quoted text") == [Found(kind: .quote, text: "> quoted text")])
    }

    @Test(arguments: [("- item", "-"), ("* item", "*"), ("+ item", "+"), ("12. item", "12."), ("  - nested", "-")])
    func listMarkersAreHighlighted(line: String, marker: String) {
        #expect(found(in: line) == [Found(kind: .listMarker, text: marker)])
    }

    // MARK: Inline elements

    @Test func strongText() {
        #expect(found(in: "a **bold** b") == [Found(kind: .strong, text: "**bold**")])
        #expect(found(in: "a __bold__ b") == [Found(kind: .strong, text: "__bold__")])
    }

    @Test func emphasizedText() {
        #expect(found(in: "an *italic* word") == [Found(kind: .emphasis, text: "*italic*")])
        #expect(found(in: "an _italic_ word") == [Found(kind: .emphasis, text: "_italic_")])
    }

    @Test func underscoresInsideWordsAreNotEmphasis() {
        #expect(found(in: "snake_case_name").isEmpty)
    }

    @Test func inlineCode() {
        #expect(found(in: "run `make test` now") == [Found(kind: .code, text: "`make test`")])
    }

    @Test func linksAndImages() {
        #expect(found(in: "see [docs](https://example.com)") == [Found(kind: .link, text: "[docs](https://example.com)")])
        #expect(found(in: "![logo](img/logo.png)") == [Found(kind: .link, text: "![logo](img/logo.png)")])
    }

    // MARK: Fenced code blocks

    @Test func fencedCodeBlockIsCodeAndHidesMarkdownInside() {
        let markdown = "```swift\nlet **x** = 1\n```\nafter **b**"

        #expect(found(in: markdown) == [
            Found(kind: .strong, text: "**b**"),
            Found(kind: .code, text: "```swift\nlet **x** = 1\n```\n"),
        ])
    }

    @Test func unclosedFenceRunsToTheEnd() {
        #expect(found(in: "```\ncode **x**") == [Found(kind: .code, text: "```\ncode **x**")])
    }

    @Test func tildeFencesWork() {
        #expect(found(in: "~~~\n# not a heading\n~~~") == [Found(kind: .code, text: "~~~\n# not a heading\n~~~")])
    }

    @Test func partOfACodeBlockIsStillCode() {
        let markdown = "```\none\ntwo\n```"
        let secondLine = NSRange(location: 8, length: 4) // "two\n"

        #expect(found(in: markdown, range: secondLine) == [Found(kind: .code, text: "two\n")])
    }

    // MARK: Invalidation

    @Test func editingAPlainLineReHighlightsJustThatLine() {
        let text = "one\ntwo\nthree" as NSString

        let range = highlighter.invalidationRange(for: NSRange(location: 5, length: 0), in: text)

        #expect(range == NSRange(location: 4, length: 4))
    }

    @Test func editingInsideACodeBlockReHighlightsTheWholeBlock() {
        let text = "intro\n```\ncode\n```\noutro" as NSString

        let range = highlighter.invalidationRange(for: NSRange(location: 11, length: 0), in: text)

        #expect(text.substring(with: range) == "```\ncode\n```\n")
    }

    @Test func editsAboveAFenceReHighlightToTheEnd() {
        // Adding or removing a fence re-pairs every fence after it.
        let text = "intro\n```\ncode\n```\noutro" as NSString

        let range = highlighter.invalidationRange(for: NSRange(location: 0, length: 0), in: text)

        #expect(range == NSRange(location: 0, length: text.length))
    }
}
