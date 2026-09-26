//
//  SyntaxHighlighter.swift
//  LF-Paper
//

import Foundation

/// What a highlighted span of text is. The editor theme maps each kind to fonts and colors.
nonisolated enum TokenKind: Sendable, Hashable {
    case heading
    case strong
    case emphasis
    case code
    case link
    case quote
    case listMarker
    case key
    case string
    case number
    case literal
    case punctuation
    case comment
}

nonisolated struct SyntaxToken: Equatable, Sendable {
    let kind: TokenKind
    let range: NSRange
}

/// Finds tokens in a document. The editor only asks about the part of the text that changed.
nonisolated protocol SyntaxHighlighter: Sendable {
    /// Tokens inside `range`. Where tokens overlap, later ones are applied on top of earlier ones.
    func tokens(in text: NSString, range: NSRange) -> [SyntaxToken]

    /// The range to re-highlight after the characters in `editedRange` changed.
    /// Defaults to the whole lines the edit touched; override for constructs spanning lines.
    func invalidationRange(for editedRange: NSRange, in text: NSString) -> NSRange
}

nonisolated extension SyntaxHighlighter {
    func invalidationRange(for editedRange: NSRange, in text: NSString) -> NSRange {
        TextRanges.lines(touching: editedRange, in: text)
    }
}

nonisolated enum TextRanges {
    /// The whole lines that `range` touches, with `range` clamped to the text first.
    static func lines(touching range: NSRange, in text: NSString) -> NSRange {
        text.paragraphRange(for: clamped(range, in: text))
    }

    /// `range` limited to the text.
    static func clamped(_ range: NSRange, in text: NSString) -> NSRange {
        let location = min(max(range.location, 0), text.length)
        let length = min(max(range.length, 0), text.length - location)
        return NSRange(location: location, length: length)
    }
}

/// The highlighter for each kind of file.
enum SyntaxHighlighters {
    static func highlighter(for kind: FileKind?) -> (any SyntaxHighlighter)? {
        switch kind {
        case .markdown: MarkdownHighlighter()
        case .json: JSONHighlighter()
        case .folder, nil: nil
        }
    }
}
