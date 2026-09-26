//
//  LargeFilePerformanceTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

/// Times the heavy paths on large files. The budgets are generous (tests run a Debug build) and
/// exist to catch accidental quadratic behaviour; the measured times are attached as a report.
@Suite(.serialized)
struct LargeFilePerformanceTests {
    /// About 10 MB of JSON: an array of records like an API export.
    private static let largeJSON: String = {
        let records = (0..<38_000).map { index in
            #"{"id":\#(index),"name":"User \#(index)","email":"user\#(index)@example.com","active":\#(index % 3 == 0),"score":\#(Double(index) * 1.5),"tags":["alpha","beta","gamma"],"address":{"street":"\#(index) Main Street","city":"Springfield","zip":"\#(10_000 + index % 90_000)"},"notes":"Lorem ipsum dolor sit amet, consectetur adipiscing elit."}"#
        }
        return "[" + records.joined(separator: ",") + "]"
    }()

    private static func measure<T>(_ body: () throws -> T) rethrows -> (T, Duration) {
        let clock = ContinuousClock()
        var result: T?
        let duration = try clock.measure { result = try body() }
        return (result!, duration)
    }

    private static func report(_ name: String, _ duration: Duration, budget: Duration) {
        let line = "\(name): \(duration.formatted(.units(allowed: [.seconds, .milliseconds], fractionalPart: .show(length: 0)))) (budget \(budget))"
        Attachment.record(line, named: "\(name).txt")
        #expect(duration < budget, "\(line)")
    }

    @Test func fixtureIsAboutTenMegabytes() {
        #expect(Self.largeJSON.utf8.count > 9_000_000)
    }

    @Test func parsingWithSourceRanges() throws {
        let (document, duration) = try Self.measure { try JSONParser.parse(Self.largeJSON, recordsSourceRanges: true) }
        #expect(document.sourceRanges.count == 38_000 * 15 + 1) // 15 values per record, plus the root array
        Self.report("parse-10MB-with-ranges", duration, budget: .seconds(10))
    }

    @Test func formattingAndMinifying() throws {
        let value = try JSONParser.parse(Self.largeJSON).value
        let (pretty, formatDuration) = Self.measure { JSONFormatter.pretty(value) }
        let (_, minifyDuration) = Self.measure { JSONFormatter.minified(value) }
        #expect(pretty.count > Self.largeJSON.count)
        Self.report("format-10MB", formatDuration, budget: .seconds(3))
        Self.report("minify-10MB", minifyDuration, budget: .seconds(3))
    }

    @Test func buildingTheTreeRoot() throws {
        let value = try JSONParser.parse(Self.largeJSON).value
        let (children, duration) = Self.measure { JSONTreeNode(root: value).children?.count ?? 0 }
        #expect(children == 38_000)
        Self.report("tree-root-10MB", duration, budget: .seconds(1))
    }

    @Test func comparingTwoLargeDocuments() throws {
        let changed = Self.largeJSON.replacingOccurrences(of: #""name":"User 20000""#, with: #""name":"Changed""#)
        let (outcome, duration) = Self.measure {
            JSONComparison.run(left: Self.largeJSON, right: changed, options: .init())
        }
        guard case .compared(let result) = outcome else {
            Issue.record("expected a comparison")
            return
        }
        #expect(result.differences.count == 1)
        Self.report("compare-10MB-one-change", duration, budget: .seconds(25))
    }

    @Test func highlightingAMinifiedLineOnEachKeystroke() {
        // Minified JSON is one line, so every keystroke re-highlights all of it (up to the 2 M character limit).
        let oneLine = String(Self.largeJSON.prefix(1_000_000)) as NSString
        let highlighter = JSONHighlighter()
        let (tokens, duration) = Self.measure {
            let range = highlighter.invalidationRange(for: NSRange(location: 500_000, length: 1), in: oneLine)
            return highlighter.tokens(in: oneLine, range: range)
        }
        #expect(!tokens.isEmpty)
        Self.report("highlight-1MB-single-line", duration, budget: .seconds(1))
    }

    @Test func renderingLargeMarkdown() {
        let section = "## Section\n\nSome **bold** text, a [link](https://example.com) and `code`.\n\n- one\n- two\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n"
        let markdown = String(repeating: section, count: 10_000) // about 1 MB
        let (html, duration) = Self.measure { MarkdownRenderer.html(from: markdown) }
        #expect(html.contains("<table>"))
        Self.report("markdown-1MB", duration, budget: .seconds(2))
    }
}
