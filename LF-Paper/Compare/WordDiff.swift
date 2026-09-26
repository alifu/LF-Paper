//
//  WordDiff.swift
//  LF-Paper
//

import Foundation

/// Which parts of a changed line differ from the line it replaced, so Compare can highlight
/// just those (`"math"` → `"math",` marks only the comma).
///
/// Lines are split into words (letters, digits and `_`), runs of whitespace, and single punctuation
/// characters, then diffed with `CollectionDifference`.
nonisolated enum WordDiff {
    /// Below this share of unchanged text, a word-by-word view is just noise; the whole line is marked.
    static let minimumSharedFraction = 0.4

    /// UTF-16 ranges that changed on each side, or `nil` when the lines have too little in common.
    static func changes(from old: String, to new: String) -> (old: [NSRange], new: [NSRange])? {
        let oldTokens = tokens(of: old)
        let newTokens = tokens(of: new)
        let difference = newTokens.map(\.text).difference(from: oldTokens.map(\.text))

        var removed = IndexSet()
        var inserted = IndexSet()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        let longest = max((old as NSString).length, (new as NSString).length)
        let shared = oldTokens.indices.filter { !removed.contains($0) }.reduce(0) { $0 + oldTokens[$1].range.length }
        guard longest > 0, Double(shared) / Double(longest) >= minimumSharedFraction else { return nil }

        return (
            merged(removed.map { oldTokens[$0].range }, in: old as NSString),
            merged(inserted.map { newTokens[$0].range }, in: new as NSString)
        )
    }

    private struct Token {
        let text: String
        let range: NSRange
    }

    private enum Category {
        case word, space, other
    }

    private static func tokens(of line: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var currentCategory: Category?
        var start = 0
        var offset = 0

        func finish() {
            guard !current.isEmpty else { return }
            tokens.append(Token(text: current, range: NSRange(location: start, length: offset - start)))
            current = ""
        }

        for character in line {
            let category = category(of: character)
            // Words and spaces grow; each punctuation mark is a token of its own.
            if category != currentCategory || category == .other {
                finish()
                start = offset
                currentCategory = category
            }
            current.append(character)
            offset += character.utf16.count
        }
        finish()
        return tokens
    }

    private static func category(of character: Character) -> Category {
        if character.isLetter || character.isNumber || character == "_" { return .word }
        if character.isWhitespace { return .space }
        return .other
    }

    /// Joins ranges that touch or are split by one unchanged punctuation mark, so "1.5" → "2.75"
    /// is one highlight on each side rather than two.
    private static func merged(_ ranges: [NSRange], in line: NSString) -> [NSRange] {
        ranges.sorted { $0.location < $1.location }.reduce(into: []) { result, range in
            guard let last = result.last else {
                result.append(range)
                return
            }
            let gap = range.location - NSMaxRange(last)
            let bridgesPunctuation = gap == 1 && !CharacterSet.whitespaces.contains(UnicodeScalar(line.character(at: NSMaxRange(last))) ?? " ")
            if gap == 0 || bridgesPunctuation {
                result[result.count - 1] = NSRange(location: last.location, length: NSMaxRange(range) - last.location)
            } else {
                result.append(range)
            }
        }
    }
}
