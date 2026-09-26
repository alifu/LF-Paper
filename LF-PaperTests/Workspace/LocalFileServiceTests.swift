//
//  LocalFileServiceTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

final class LocalFileServiceTests {
    private let folder: TemporaryDirectory
    private let service = LocalFileService()

    init() throws {
        folder = try TemporaryDirectory()
    }

    // MARK: Listing

    @Test func listsFoldersFirstThenSupportedFilesByName() throws {
        try folder.makeFile("b.md")
        try folder.makeFile("A.json")
        try folder.makeFile("image.png")
        try folder.makeFolder("zeta")
        try folder.makeFolder("Alpha")

        let names = try service.contents(of: folder.url, includeHidden: false).map(\.name)

        #expect(names == ["Alpha", "zeta", "A.json", "b.md"])
    }

    @Test func classifiesItemKinds() throws {
        try folder.makeFile("readme.markdown")
        try folder.makeFile("data.JSON")
        try folder.makeFolder("docs")

        let kinds = try service.contents(of: folder.url, includeHidden: false)
            .reduce(into: [String: FileKind]()) { $0[$1.name] = $1.kind }

        #expect(kinds == ["docs": .folder, "data.JSON": .json, "readme.markdown": .markdown])
    }

    @Test func sortsNumberedNamesNaturally() throws {
        try folder.makeFile("note 10.md")
        try folder.makeFile("note 2.md")

        let names = try service.contents(of: folder.url, includeHidden: false).map(\.name)

        #expect(names == ["note 2.md", "note 10.md"])
    }

    @Test func hidesDotFilesUnlessRequested() throws {
        try folder.makeFile(".draft.md")
        try folder.makeFile("visible.md")

        let hidden = try service.contents(of: folder.url, includeHidden: false).map(\.name)
        let all = try service.contents(of: folder.url, includeHidden: true).map(\.name)

        #expect(hidden == ["visible.md"])
        #expect(all.contains(".draft.md"))
    }

    @Test func listingMissingFolderThrowsFileNotFound() {
        let missing = folder.url.appending(path: "missing", directoryHint: .isDirectory)

        #expect(throws: AppError.fileNotFound(missing)) {
            try service.contents(of: missing, includeHidden: false)
        }
    }

    // MARK: Reading and writing

    @Test func readsUTF8Text() throws {
        let file = try folder.makeFile("notes.md", contents: "# Héllo")

        #expect(try service.read(file) == "# Héllo")
    }

    @Test func readingMissingFileThrowsFileNotFound() {
        let missing = folder.url.appending(path: "missing.md")

        #expect(throws: AppError.fileNotFound(missing)) {
            try service.read(missing)
        }
    }

    @Test func writeReplacesContents() throws {
        let file = try folder.makeFile("notes.md", contents: "old")

        try service.write("new", to: file)

        #expect(try folder.contents(of: "notes.md") == "new")
    }

    // MARK: Creating

    @Test func createFileMakesAnEmptyFile() throws {
        let file = try service.createFile(named: "new.md", in: folder.url)

        #expect(file.lastPathComponent == "new.md")
        #expect(try folder.contents(of: "new.md") == "")
    }

    @Test func createFileRejectsExistingName() throws {
        try folder.makeFile("taken.md", contents: "keep me")
        let existing = folder.url.appending(path: "taken.md", directoryHint: .notDirectory)

        #expect(throws: AppError.alreadyExists(existing)) {
            try service.createFile(named: "taken.md", in: folder.url)
        }
        #expect(try folder.contents(of: "taken.md") == "keep me")
    }

    @Test func createFileRejectsInvalidName() {
        #expect(throws: AppError.invalidName("a/b")) {
            try service.createFile(named: "a/b", in: folder.url)
        }
    }

    @Test func createFolderMakesADirectory() throws {
        let created = try service.createFolder(named: "drafts", in: folder.url)

        #expect(created.lastPathComponent == "drafts")
        #expect(try service.contents(of: folder.url, includeHidden: false).map(\.kind) == [.folder])
    }

    // MARK: Renaming and deleting

    @Test func renameMovesTheItem() throws {
        let file = try folder.makeFile("old.md", contents: "text")

        let renamed = try service.rename(file, to: "new.md")

        #expect(renamed.lastPathComponent == "new.md")
        #expect(!folder.exists("old.md"))
        #expect(try folder.contents(of: "new.md") == "text")
    }

    @Test func renameToExistingNameThrows() throws {
        let file = try folder.makeFile("a.md")
        try folder.makeFile("b.md")

        #expect(throws: AppError.alreadyExists(folder.url.appending(path: "b.md", directoryHint: .notDirectory))) {
            try service.rename(file, to: "b.md")
        }
        #expect(folder.exists("a.md"))
    }

    @Test func renameCanChangeOnlyTheCase() throws {
        let file = try folder.makeFile("note.md")

        _ = try service.rename(file, to: "Note.md")

        #expect(try service.contents(of: folder.url, includeHidden: false).map(\.name) == ["Note.md"])
    }

    @Test func moveToTrashRemovesTheItem() throws {
        let file = try folder.makeFile("trash-me.md")

        try service.moveToTrash(file)

        #expect(!folder.exists("trash-me.md"))
    }

    @Test func existsReflectsTheDisk() throws {
        let file = try folder.makeFile("here.md")

        #expect(service.exists(file))
        #expect(!service.exists(folder.url.appending(path: "gone.md")))
    }
}
