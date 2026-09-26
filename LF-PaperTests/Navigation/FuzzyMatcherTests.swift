//
//  FuzzyMatcherTests.swift
//  LF-PaperTests
//

import Testing
@testable import LF_Paper

struct FuzzyMatcherTests {
    private func score(_ query: String, _ candidate: String) -> Int? {
        FuzzyMatcher.match(query, in: candidate)?.score
    }

    @Test func lettersMustAppearInOrder() {
        #expect(FuzzyMatcher.match("rdm", in: "README.md") != nil)
        #expect(FuzzyMatcher.match("mdr", in: "README.md") == nil)
        #expect(FuzzyMatcher.match("x", in: "README.md") == nil)
    }

    @Test func ignoresCaseAndSpaces() {
        #expect(FuzzyMatcher.match("read me", in: "docs/README.md") != nil)
        #expect(FuzzyMatcher.match("DATA", in: "data.json") != nil)
    }

    @Test func emptyQueryMatchesEverythingEqually() throws {
        let match = try #require(FuzzyMatcher.match("", in: "a.md"))

        #expect(match.score == 0)
        #expect(match.matchedOffsets.isEmpty)
    }

    @Test func reportsWhichCharactersMatched() throws {
        let match = try #require(FuzzyMatcher.match("dj", in: "data.json"))

        #expect(match.matchedOffsets == [0, 5])
    }

    @Test func consecutiveLettersBeatScatteredOnes() throws {
        let together = try #require(score("json", "data.json"))
        let scattered = try #require(score("json", "j_s_o_n.md"))

        #expect(together > scattered)
    }

    @Test func theFileNameBeatsAFolderName() throws {
        let inName = try #require(score("read", "docs/README.md"))
        let inFolder = try #require(score("read", "readings/notes.md"))

        #expect(inName > inFolder)
    }

    @Test func startsOfWordsBeatTheMiddleOfWords() throws {
        let wordStarts = try #require(score("wm", "WorkspaceModel.md"))
        let middle = try #require(score("wm", "swim.md"))

        #expect(wordStarts > middle)
    }

    @Test func prefersTheBestPlacementNotTheFirst() throws {
        // A greedy match would start at the "c" in "archive"; the best one is the whole file name.
        let match = try #require(FuzzyMatcher.match("cache", in: "archive/cache.json"))

        #expect(match.matchedOffsets == Array(8...12))
    }
}
