//
//  SwiftHighlighter.swift
//  LF-Paper
//

import Foundation

/// Simple editor highlighting for Swift files (such as generated models): keywords, attributes,
/// literals, numbers, strings and line comments. Block comments and multi-line strings aren't
/// recognised.
nonisolated struct SwiftHighlighter: SyntaxHighlighter {
    private static let keywords = [
        "actor", "any", "as", "associatedtype", "async", "await", "break", "case", "catch", "class", "continue",
        "default", "defer", "deinit", "do", "else", "enum", "extension", "fallthrough", "fileprivate", "final",
        "for", "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "let", "mutating",
        "nonisolated", "open", "operator", "override", "private", "protocol", "public", "repeat", "rethrows",
        "return", "self", "Self", "some", "static", "struct", "subscript", "super", "switch", "throw", "throws",
        "try", "typealias", "var", "where", "while",
    ]

    /// Applied in order; later rules win where tokens overlap, so strings and comments come last.
    private static let rules = RegexHighlighter(rules: [
        // Not inside backticks, where a keyword is an ordinary name.
        .init(.keyword, pattern: "(?<!`)\\b(?:\(keywords.joined(separator: "|")))\\b(?!`)"),
        .init(.literal, pattern: #"\b(?:true|false|nil)\b"#),
        .init(.number, pattern: #"\b(?:0x[0-9A-Fa-f_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)\b"#),
        .init(.key, pattern: #"@\w+"#),
        .init(.string, pattern: #""(?:[^"\\\n]|\\.)*""#),
        // A `//` that isn't inside a string: skip over whole strings before it.
        .init(.comment, pattern: #"^(?:[^"\n/]|/(?!/)|"(?:[^"\\\n]|\\.)*")*(//.*)$"#, captureGroup: 1),
    ])

    func tokens(in text: NSString, range: NSRange) -> [SyntaxToken] {
        Self.rules.tokens(in: text, range: range)
    }
}
