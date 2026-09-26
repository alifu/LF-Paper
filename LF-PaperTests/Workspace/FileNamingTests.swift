//
//  FileNamingTests.swift
//  LF-PaperTests
//

import Testing
@testable import LF_Paper

struct FileNamingTests {

    @Test func validateTrimsSurroundingWhitespace() throws {
        #expect(try FileNaming.validate("  notes.md \n") == "notes.md")
    }

    @Test(arguments: ["", "   ", ".", "..", "a/b", "a:b"])
    func validateRejectsUnusableNames(name: String) {
        #expect(throws: AppError.invalidName(name)) {
            try FileNaming.validate(name)
        }
    }

    @Test func validateAllowsHiddenFileNames() throws {
        #expect(try FileNaming.validate(".env.json") == ".env.json")
    }

    @Test func uniqueNameReturnsBaseNameWhenFree() {
        let name = FileNaming.uniqueName(base: "Untitled", fileExtension: "md", existing: ["other.md"])

        #expect(name == "Untitled.md")
    }

    @Test func uniqueNameAppendsTheFirstFreeNumber() {
        let name = FileNaming.uniqueName(
            base: "Untitled",
            fileExtension: "md",
            existing: ["Untitled.md", "Untitled 2.md"]
        )

        #expect(name == "Untitled 3.md")
    }

    @Test func uniqueNameIgnoresCase() {
        let name = FileNaming.uniqueName(base: "Untitled", fileExtension: "md", existing: ["untitled.MD"])

        #expect(name == "Untitled 2.md")
    }

    @Test func uniqueNameWithoutExtensionIsForFolders() {
        let name = FileNaming.uniqueName(base: "New Folder", fileExtension: nil, existing: ["New Folder"])

        #expect(name == "New Folder 2")
    }
}
