//
//  QuickOpenRankingTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

struct QuickOpenRankingTests {
    private static let root = URL(filePath: "/project", directoryHint: .isDirectory)

    private func files(_ paths: String...) -> [IndexedFile] {
        paths.compactMap { IndexedFile(root: Self.root, relativePath: $0) }
    }

    private func url(_ path: String) -> URL {
        Self.root.appending(path: path)
    }

    private func ranked(_ query: String, _ files: [IndexedFile], recent: [URL] = [], limit: Int = 50) -> [String] {
        QuickOpenRanking.rank(query: query, files: files, recent: recent, limit: limit).map(\.file.relativePath)
    }

    @Test func leavesOutFilesThatDoNotMatch() {
        #expect(ranked("json", files("a.md", "data.json", "notes/b.md")) == ["data.json"])
    }

    @Test func putsTheBestMatchFirst() {
        let all = files("notes/readings.md", "docs/README.md", "src/reader/deep.json")

        #expect(ranked("readme", all).first == "docs/README.md")
    }

    @Test func recentlyOpenedFilesWinCloseCalls() {
        let all = files("a/config.json", "b/config.json")

        #expect(ranked("config", all) == ["a/config.json", "b/config.json"])
        #expect(ranked("config", all, recent: [url("b/config.json")]) == ["b/config.json", "a/config.json"])
    }

    @Test func emptyQueryListsRecentFilesFirstThenTheRestByPath() {
        let all = files("c.md", "a.md", "b.json")

        #expect(ranked("", all, recent: [url("b.json")]) == ["b.json", "a.md", "c.md"])
    }

    @Test func recentFilesThatAreGoneAreIgnored() {
        #expect(ranked("", files("a.md"), recent: [url("deleted.md")]) == ["a.md"])
    }

    @Test func stopsAtTheLimit() {
        let many = (1...30).compactMap { IndexedFile(root: Self.root, relativePath: "note\($0).md") }

        #expect(ranked("note", many, limit: 10).count == 10)
    }

    @Test func resultsCarryTheMatchedCharactersOfTheFileName() throws {
        let result = try #require(QuickOpenRanking.rank(query: "rd", files: files("docs/README.md"), recent: [], limit: 5).first)

        #expect(result.file.name == "README.md")
        #expect(result.nameMatchOffsets == [0, 3])
    }
}
