//
//  FileKindTests.swift
//  LF-PaperTests
//

import Testing
@testable import LF_Paper

struct FileKindTests {
    @Test(arguments: [("md", FileKind.markdown), ("MARKDOWN", .markdown), ("json", .json), ("swift", .swift)])
    func supportedExtensions(fileExtension: String, kind: FileKind) {
        #expect(FileKind(fileExtension: fileExtension) == kind)
    }

    @Test func otherExtensionsAreNotShown() {
        #expect(FileKind(fileExtension: "txt") == nil)
    }

    @Test func eachKindHasASpokenName() {
        #expect(FileKind.folder.accessibilityName == "folder")
        #expect(FileKind.markdown.accessibilityName == "Markdown file")
        #expect(FileKind.json.accessibilityName == "JSON file")
        #expect(FileKind.swift.accessibilityName == "Swift file")
    }
}
