//
//  FolderSearchTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

/// Searching the files of a folder: which files are read, and how results arrive.
struct FolderSearchTests {
    private let folder: TemporaryDirectory

    init() throws {
        folder = try TemporaryDirectory()
    }

    private func target(_ path: String, contents: String, unsavedText: String? = nil) throws -> SearchTarget {
        try folder.makeFile(path, contents: contents)
        let file = try #require(IndexedFile(root: folder.url, relativePath: path))
        return SearchTarget(file: file, unsavedText: unsavedText)
    }

    private func query(_ text: String) -> SearchQuery {
        SearchQuery(text: text, options: SearchOptions())
    }

    @Test func findsMatchesInAFile() throws {
        let file = try target("a.md", contents: "one needle\ntwo needle")

        let result = try #require(FolderSearch.search(file, for: query("needle").regularExpression()))

        #expect(result.matches.map(\.lineNumber) == [1, 2])
    }

    @Test func filesWithoutMatchesGiveNoResult() throws {
        let file = try target("a.md", contents: "nothing here")

        #expect(FolderSearch.search(file, for: try query("needle").regularExpression()) == nil)
    }

    @Test func searchesUnsavedEditsInsteadOfTheDisk() throws {
        let file = try target("a.md", contents: "old text", unsavedText: "new needle")

        let result = try #require(FolderSearch.search(file, for: query("needle").regularExpression()))

        #expect(result.matches.count == 1)
    }

    @Test func skipsVeryLargeFiles() throws {
        let big = try target("big.json", contents: "needle" + String(repeating: " ", count: 64))

        #expect(FolderSearch.search(big, for: try query("needle").regularExpression(), maximumFileSize: 32) == nil)
    }

    @Test func skipsFilesThatAreNotText() throws {
        let binary = try target("binary.md", contents: "needle\u{0}\u{1}")

        #expect(FolderSearch.search(binary, for: try query("needle").regularExpression()) == nil)
    }

    @Test func streamsOneResultPerMatchingFileInOrder() async throws {
        let targets = [
            try target("a.md", contents: "needle"),
            try target("b.md", contents: "nothing"),
            try target("c.json", contents: #"{"needle": "needle"}"#),
        ]

        var names: [String] = []
        for await result in FolderSearch.results(for: query("needle"), in: targets) {
            names.append("\(result.file.name):\(result.matches.count)")
        }

        #expect(names == ["a.md:1", "c.json:2"])
    }
}
