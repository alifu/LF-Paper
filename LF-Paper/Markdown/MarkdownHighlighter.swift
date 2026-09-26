//
//  MarkdownHighlighter.swift
//  LF-Paper
//

import Foundation

/// Editor highlighting for Markdown: headings, quotes, list markers, emphasis, links, inline code
/// and fenced code blocks. Markdown inside a fenced block is shown as plain code.
nonisolated struct MarkdownHighlighter: SyntaxHighlighter {
    /// Applied in order; later rules win where tokens overlap (so code beats emphasis).
    private static let inlineRules = RegexHighlighter(rules: [
        .init(.heading, pattern: #"^[ \t]{0,3}#{1,6}(?:[ \t].*)?$"#),
        .init(.quote, pattern: #"^[ \t]{0,3}>.*$"#),
        .init(.listMarker, pattern: #"^[ \t]*([-*+]|\d{1,9}[.)])(?=[ \t])"#, captureGroup: 1),
        .init(.strong, pattern: #"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#),
        .init(.emphasis, pattern: #"(?<![\w*])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![\w*])"#),
        .init(.emphasis, pattern: #"(?<![\w_])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![\w_])"#),
        .init(.link, pattern: #"!?\[[^\]\n]*\]\([^)\n]*\)"#),
        .init(.code, pattern: #"`[^`\n]+`"#),
    ])

    private static let fenceLine = RegexHighlighter.Rule(.code, pattern: #"^[ \t]{0,3}(?:```|~~~)"#)

    func tokens(in text: NSString, range: NSRange) -> [SyntaxToken] {
        let blocks = Self.fencedBlocks(in: text)
        let inline = Self.inlineRules.tokens(in: text, range: range).filter { token in
            !blocks.contains { NSIntersectionRange($0, token.range).length > 0 }
        }
        let code = blocks.compactMap { block -> SyntaxToken? in
            let visible = NSIntersectionRange(block, range)
            return visible.length > 0 ? SyntaxToken(kind: .code, range: visible) : nil
        }
        return inline + code
    }

    /// Fences pair up across the whole document, so one edit can change everything after it:
    /// editing a fence (or a line above one) re-highlights to the end; editing inside a block
    /// re-highlights that block.
    func invalidationRange(for editedRange: NSRange, in text: NSString) -> NSRange {
        let lines = TextRanges.lines(touching: editedRange, in: text)
        let toEnd = NSRange(location: lines.location, length: text.length - lines.location)
        if Self.hasFence(in: text, range: lines) {
            return toEnd
        }
        let touchedBlocks = Self.fencedBlocks(in: text).filter { NSIntersectionRange($0, lines).length > 0 }
        if !touchedBlocks.isEmpty {
            return touchedBlocks.reduce(lines) { NSUnionRange($0, $1) }
        }
        return Self.hasFence(in: text, range: toEnd) ? toEnd : lines
    }

    /// Fenced code blocks including their fence lines. An unclosed fence runs to the end.
    static func fencedBlocks(in text: NSString) -> [NSRange] {
        let fullRange = NSRange(location: 0, length: text.length)
        let fences = fenceLine.regex.matches(in: text as String, range: fullRange)
            .map { text.lineRange(for: $0.range) }
        return stride(from: 0, to: fences.count, by: 2).map { index in
            let start = fences[index].location
            let end = index + 1 < fences.count ? NSMaxRange(fences[index + 1]) : text.length
            return NSRange(location: start, length: end - start)
        }
    }

    private static func hasFence(in text: NSString, range: NSRange) -> Bool {
        fenceLine.regex.firstMatch(in: text as String, range: range) != nil
    }
}
