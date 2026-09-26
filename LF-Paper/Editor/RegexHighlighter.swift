//
//  RegexHighlighter.swift
//  LF-Paper
//

import Foundation

/// A highlighter driven by a list of regular-expression rules, applied in order.
nonisolated struct RegexHighlighter: SyntaxHighlighter {
    // @unchecked: NSRegularExpression is immutable and documented as safe to share between threads.
    nonisolated struct Rule: @unchecked Sendable {
        let kind: TokenKind
        let regex: NSRegularExpression
        /// Which capture group is the token; 0 is the whole match.
        let captureGroup: Int

        /// Patterns are fixed in code and covered by tests, so an invalid one is a programming error.
        init(
            _ kind: TokenKind,
            pattern: String,
            options: NSRegularExpression.Options = [.anchorsMatchLines],
            captureGroup: Int = 0
        ) {
            do {
                regex = try NSRegularExpression(pattern: pattern, options: options)
            } catch {
                preconditionFailure("Invalid highlighting pattern \(pattern): \(error)")
            }
            self.kind = kind
            self.captureGroup = captureGroup
        }
    }

    let rules: [Rule]

    func tokens(in text: NSString, range: NSRange) -> [SyntaxToken] {
        let string = text as String
        return rules.flatMap { rule in
            rule.regex.matches(in: string, range: range).compactMap { match in
                let tokenRange = match.range(at: rule.captureGroup)
                guard tokenRange.location != NSNotFound else { return nil }
                return SyntaxToken(kind: rule.kind, range: tokenRange)
            }
        }
    }
}
