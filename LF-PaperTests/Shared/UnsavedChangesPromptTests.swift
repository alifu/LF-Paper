//
//  UnsavedChangesPromptTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

@MainActor
struct UnsavedChangesPromptTests {
    private func document(_ name: String) -> OpenDocument {
        OpenDocument(url: URL(filePath: "/tmp/\(name)"), text: "")
    }

    @Test func namesTheFileWhenThereIsOnlyOne() {
        #expect(UnsavedChangesPrompt.message(for: [document("a.md")]) == "Do you want to save the changes you made to “a.md”?")
    }

    @Test func countsTheFilesWhenThereAreSeveral() {
        let message = UnsavedChangesPrompt.message(for: [document("a.md"), document("b.json")])

        #expect(message == "You have unsaved changes in 2 files. Do you want to save them?")
    }
}
