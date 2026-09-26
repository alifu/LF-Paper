//
//  FileIndexerTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

/// The list of every Markdown and JSON file under a folder, for Quick Open and search.
struct FileIndexerTests {
    private let folder: TemporaryDirectory

    init() throws {
        folder = try TemporaryDirectory()
        try folder.makeFile("README.md")
        try folder.makeFile("data.json")
        try folder.makeFile("image.png")
        try folder.makeFile("docs/guide/intro.markdown")
        try folder.makeFile(".hidden/secret.md")
        try folder.makeFile(".notes.md")
        try folder.makeFile("node_modules/pkg/package.json")
        try folder.makeFolder("App.app/Contents")
        try folder.makeFile("App.app/Contents/inside.json")
    }

    @Test func findsSupportedFilesInEveryFolderSortedByPath() {
        let files = FileIndexer.index(root: folder.url, includeHidden: false)

        #expect(files.map(\.relativePath) == ["data.json", "docs/guide/intro.markdown", "README.md"])
        #expect(files.map(\.kind) == [.json, .markdown, .markdown])
    }

    @Test func includesHiddenFilesOnlyWhenAsked() {
        let files = FileIndexer.index(root: folder.url, includeHidden: true)

        #expect(files.map(\.relativePath).contains(".hidden/secret.md"))
        #expect(files.map(\.relativePath).contains(".notes.md"))
    }

    @Test func skipsDependencyFoldersAndPackages() {
        let paths = FileIndexer.index(root: folder.url, includeHidden: true).map(\.relativePath)

        #expect(!paths.contains { $0.hasPrefix("node_modules/") })
        #expect(!paths.contains { $0.hasPrefix("App.app/") })
    }

    @Test func urlsAreSpelledLikeTheRootSoTheSidebarCanFindThem() throws {
        let file = try #require(FileIndexer.index(root: folder.url, includeHidden: false).first { $0.name == "intro.markdown" })

        #expect(file.url == folder.url.appending(path: "docs/guide/intro.markdown"))
    }

    @Test func stopsAtTheFileLimit() {
        let files = FileIndexer.index(root: folder.url, includeHidden: false, limit: 2)

        #expect(files.count == 2)
    }
}
