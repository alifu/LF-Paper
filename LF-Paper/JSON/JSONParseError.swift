//
//  JSONParseError.swift
//  LF-Paper
//

import Foundation

/// Why and where JSON text failed to parse. Line and column are 1-based.
nonisolated struct JSONParseError: Error, Equatable, Sendable {
    nonisolated enum Reason: Equatable, Sendable {
        case unexpectedEnd(expected: String)
        case unexpectedCharacter(found: String, expected: String)
        case invalidNumber
        case invalidEscape
        case unescapedControlCharacter
        case unterminatedString
        case trailingContent
        case nestingTooDeep(limit: Int)
    }

    private static let lineFeed: UInt16 = 0x0A

    let reason: Reason
    /// UTF-16 offset, as used by `NSTextView`.
    let offset: Int
    let line: Int
    let column: Int

    init(reason: Reason, offset: Int, in units: [UInt16]) {
        self.reason = reason
        self.offset = offset
        let before = units[..<min(offset, units.count)]
        line = before.count { $0 == Self.lineFeed } + 1
        let lineStart = before.lastIndex(of: Self.lineFeed).map { $0 + 1 } ?? 0
        column = offset - lineStart + 1
    }
}

nonisolated extension JSONParseError: LocalizedError {
    var errorDescription: String? {
        "Line \(line), column \(column): \(explanation)"
    }

    private var explanation: String {
        switch reason {
        case .unexpectedEnd(let expected):
            "Expected \(expected) but the text ended."
        case .unexpectedCharacter(let found, let expected):
            "Expected \(expected) but found “\(found)”."
        case .invalidNumber:
            "This number isn’t valid JSON."
        case .invalidEscape:
            "Invalid escape sequence in a string."
        case .unescapedControlCharacter:
            "Tabs, line breaks and other control characters must be escaped inside strings."
        case .unterminatedString:
            "This string is never closed."
        case .trailingContent:
            "Unexpected text after the JSON value."
        case .nestingTooDeep(let limit):
            "Nesting is deeper than \(limit) levels."
        }
    }
}
