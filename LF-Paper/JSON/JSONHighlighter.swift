//
//  JSONHighlighter.swift
//  LF-Paper
//

import Foundation

/// Editor highlighting for JSON. Rules run in order and later ones paint over earlier ones,
/// so anything inside a string (digits, `true`, `:`) ends up colored as the string.
nonisolated struct JSONHighlighter: SyntaxHighlighter {
    private static let stringPattern = #""(?:[^"\\\n]|\\.)*""#

    private static let rules = RegexHighlighter(rules: [
        .init(.punctuation, pattern: #"[{}\[\],:]"#),
        .init(.number, pattern: #"-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?"#),
        .init(.literal, pattern: #"\b(?:true|false|null)\b"#),
        .init(.string, pattern: stringPattern),
        .init(.key, pattern: "(\(stringPattern))\\s*:", captureGroup: 1),
    ])

    func tokens(in text: NSString, range: NSRange) -> [SyntaxToken] {
        Self.rules.tokens(in: text, range: range)
    }
}
