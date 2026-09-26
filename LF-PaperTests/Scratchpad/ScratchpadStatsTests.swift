//
//  ScratchpadStatsTests.swift
//  LF-PaperTests
//

import Testing
@testable import LF_Paper

struct ScratchpadStatsTests {
    @Test func emptyTextHasNoCharactersWordsOrLines() {
        let stats = ScratchpadStats(text: "")

        #expect(stats == ScratchpadStats(characters: 0, words: 0, lines: 0))
    }

    @Test func oneWordIsOneLine() {
        let stats = ScratchpadStats(text: "hello")

        #expect(stats == ScratchpadStats(characters: 5, words: 1, lines: 1))
    }

    @Test func countsEveryLineIncludingATrailingEmptyOne() {
        #expect(ScratchpadStats(text: "one\ntwo three\nfour").lines == 3)
        #expect(ScratchpadStats(text: "one\n").lines == 2) // the editor shows the empty line after it too
        #expect(ScratchpadStats(text: "one\r\ntwo").lines == 2)
    }

    @Test func extraWhitespaceDoesNotMakeWords() {
        let stats = ScratchpadStats(text: "  write   a\n\n\tprompt  ")

        #expect(stats.words == 3)
    }

    @Test func charactersAreWhatTheUserSees() {
        #expect(ScratchpadStats(text: "👍🏽").characters == 1)
        #expect(ScratchpadStats(text: "e\u{301}").characters == 1) // e + combining acute accent
        #expect(ScratchpadStats(text: "🇮🇩 flag").words == 2)
    }
}
