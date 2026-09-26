//
//  TextSearch.swift
//  LF-Paper
//

import Foundation

/// Search in Folder options (the Aa, whole-word and .* buttons).
nonisolated struct SearchOptions: Equatable, Sendable {
    var matchesCase = false
    var matchesWholeWord = false
    var usesRegularExpression = false
}

nonisolated enum SearchQueryError: Error, Equatable, Sendable, LocalizedError {
    case emptyQuery
    case invalidPattern(String)

    var errorDescription: String? {
        switch self {
        case .emptyQuery: "Type something to search for."
        case .invalidPattern(let pattern): "“\(pattern)” isn’t a valid regular expression."
        }
    }
}

/// What to look for, turned into one regular expression for every mode.
nonisolated struct SearchQuery: Equatable, Sendable {
    let text: String
    let options: SearchOptions

    func regularExpression() throws(SearchQueryError) -> NSRegularExpression {
        guard !text.isEmpty else { throw .emptyQuery }
        var pattern = options.usesRegularExpression ? text : NSRegularExpression.escapedPattern(for: text)
        if options.matchesWholeWord {
            pattern = #"\b(?:"# + pattern + #")\b"#
        }
        do {
            return try NSRegularExpression(pattern: pattern, options: options.matchesCase ? [] : [.caseInsensitive])
        } catch {
            throw .invalidPattern(text)
        }
    }
}

/// One match: where it is in the file (UTF-16, as the editor uses) and a one-line preview.
nonisolated struct TextMatch: Equatable, Sendable, Identifiable {
    let range: NSRange
    /// 1-based.
    let lineNumber: Int
    /// The matching line without leading whitespace, shortened around the match when long.
    let preview: String
    /// The match within `preview`.
    let previewRange: NSRange

    var id: Int { range.location }
}

/// Finds every match of an expression in a text, with line numbers and previews.
nonisolated enum TextSearch {
    /// How much of a long line to keep before and after the match in the preview.
    private static let previewContextBefore = 40
    private static let previewContextAfter = 120
    private static let ellipsis = "…"

    static func matches(of expression: NSRegularExpression, in text: String, limit: Int) -> [TextMatch] {
        let string = text as NSString
        let lines = LineIndex(text: string)
        var matches: [TextMatch] = []
        expression.enumerateMatches(in: text, range: NSRange(location: 0, length: string.length)) { result, _, stop in
            guard let range = result?.range, range.length > 0 else { return }
            matches.append(match(at: range, in: string, lines: lines))
            if matches.count >= limit { stop.pointee = true }
        }
        return matches
    }

    private static func match(at range: NSRange, in string: NSString, lines: LineIndex) -> TextMatch {
        let lineNumber = lines.lineNumber(at: range.location)
        let lineRange = string.lineRange(for: NSRange(location: range.location, length: 0))
        var start = lineRange.location
        var end = NSMaxRange(lineRange)
        // Trailing line break and leading indentation aren't useful in a one-line preview.
        while end > start, let scalar = UnicodeScalar(string.character(at: end - 1)), CharacterSet.newlines.contains(scalar) {
            end -= 1
        }
        while start < range.location, let scalar = UnicodeScalar(string.character(at: start)), CharacterSet.whitespaces.contains(scalar) {
            start += 1
        }
        let clippedStart = max(start, range.location - previewContextBefore)
        let clippedEnd = min(end, NSMaxRange(range) + previewContextAfter)
        let excerptRange = string.rangeOfComposedCharacterSequences(for: NSRange(location: clippedStart, length: clippedEnd - clippedStart))

        let prefix = excerptRange.location > start ? ellipsis : ""
        let suffix = NSMaxRange(excerptRange) < end ? ellipsis : ""
        let preview = prefix + string.substring(with: excerptRange) + suffix
        let previewRange = NSRange(
            location: (prefix as NSString).length + range.location - excerptRange.location,
            length: min(range.length, NSMaxRange(excerptRange) - range.location)
        )
        return TextMatch(range: range, lineNumber: lineNumber, preview: preview, previewRange: previewRange)
    }
}
