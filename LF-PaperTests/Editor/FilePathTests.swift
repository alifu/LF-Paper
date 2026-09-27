//
//  FilePathTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

/// The parts of a file's path shown in the path bar.
struct FilePathTests {
    private let home = URL(filePath: "/Users/ada", directoryHint: .isDirectory)
    private let root = URL(filePath: "/Users/ada/Projects/Notes", directoryHint: .isDirectory)

    private func names(_ segments: [PathSegment]) -> [String] { segments.map(\.name) }

    @Test func aFileInTheFolderStartsAtTheFolder() {
        let file = root.appending(path: "docs/guide/setup.md")

        let segments = FilePath.segments(of: file, root: root, homeDirectory: home)

        #expect(names(segments) == ["Notes", "docs", "guide", "setup.md"])
        #expect(segments.map(\.isFolder) == [true, true, true, false])
        #expect(segments.allSatisfy { $0.isInWorkspace })
        #expect(segments[2].url.pathComponents.suffix(3) == ["Notes", "docs", "guide"])
        #expect(segments[3].url == file)
    }

    @Test func aFileAtTheTopOfTheFolder() {
        let segments = FilePath.segments(of: root.appending(path: "README.md"), root: root, homeDirectory: home)

        #expect(names(segments) == ["Notes", "README.md"])
    }

    @Test func spellingDifferencesDontMatter() {
        let file = URL(filePath: "/Users/ada/Projects/Notes/./docs/a.md")

        let segments = FilePath.segments(of: file, root: URL(filePath: "/Users/ada/Projects/Notes/"), homeDirectory: home)

        #expect(names(segments) == ["Notes", "docs", "a.md"])
    }

    @Test func aFileOutsideTheFolderUnderHomeStartsWithATilde() {
        let segments = FilePath.segments(of: URL(filePath: "/Users/ada/Desktop/todo.md"), root: root, homeDirectory: home)

        #expect(names(segments) == ["~", "Desktop", "todo.md"])
        #expect(segments[0].url == home)
        #expect(segments.allSatisfy { !$0.isInWorkspace })
    }

    @Test func aFileElsewhereShowsItsFullPath() {
        let segments = FilePath.segments(of: URL(filePath: "/tmp/data/x.json"), root: nil, homeDirectory: home)

        #expect(names(segments) == ["tmp", "data", "x.json"])
        #expect(segments[0].url.path(percentEncoded: false).hasPrefix("/tmp"))
    }

    @Test func relativePaths() {
        #expect(FilePath.relativePath(of: root.appending(path: "docs/a.md"), root: root) == "docs/a.md")
        #expect(FilePath.relativePath(of: root.appending(path: "docs", directoryHint: .isDirectory), root: root) == "docs")
        #expect(FilePath.relativePath(of: URL(filePath: "/tmp/a.md"), root: root) == nil)
        #expect(FilePath.relativePath(of: root, root: root) == nil)
        #expect(FilePath.relativePath(of: URL(filePath: "/tmp/a.md"), root: nil) == nil)
    }
}

/// Shortening a long path for the path bar.
struct PathBarShorteningTests {
    private let segments = ["Notes", "a", "b", "c", "file.md"].enumerated().map { index, name in
        PathSegment(name: name, url: URL(filePath: "/x/\(index)"), isFolder: name != "file.md", isInWorkspace: true)
    }

    private func names(_ parts: [PathBar.Part]) -> [String] {
        parts.map { part in
            switch part {
            case .segment(let segment): segment.name
            case .ellipsis: "…"
            }
        }
    }

    @Test func nothingHiddenShowsEveryPart() {
        #expect(names(PathBar.shortened(segments, hiding: 0)) == ["Notes", "a", "b", "c", "file.md"])
    }

    @Test func foldersAfterTheFirstAreHiddenFromTheFront() {
        #expect(names(PathBar.shortened(segments, hiding: 1)) == ["Notes", "…", "b", "c", "file.md"])
        #expect(names(PathBar.shortened(segments, hiding: 3)) == ["Notes", "…", "file.md"])
    }

    @Test func theFileIsNeverHidden() {
        #expect(names(PathBar.shortened(segments, hiding: 4)) == ["Notes", "a", "b", "c", "file.md"]) // nothing sensible to hide
        #expect(names(PathBar.shortened(Array(segments.suffix(1)), hiding: 1)) == ["file.md"])
    }
}
