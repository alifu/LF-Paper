//
//  ScratchpadStats.swift
//  LF-Paper
//

/// Character, word and line counts for the scratchpad bar.
nonisolated struct ScratchpadStats: Equatable, Sendable {
    /// User-perceived characters, so an emoji or an accented letter counts once.
    let characters: Int
    /// Runs of text between whitespace or line breaks.
    let words: Int
    /// Lines as the editor numbers them: a trailing line break starts another (empty) line.
    let lines: Int

    init(characters: Int, words: Int, lines: Int) {
        self.characters = characters
        self.words = words
        self.lines = lines
    }

    init(text: String) {
        characters = text.count
        words = text.split(whereSeparator: \.isWhitespace).count
        lines = text.isEmpty ? 0 : text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
    }
}
