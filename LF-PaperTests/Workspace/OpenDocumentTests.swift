//
//  OpenDocumentTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

struct OpenDocumentTests {
    private let document = OpenDocument(url: URL(filePath: "/tmp/notes.md"), text: "saved")

    @Test func newDocumentIsClean() {
        #expect(!document.isDirty)
    }

    @Test func editingReturnsDirtyCopyAndLeavesOriginalUntouched() {
        let edited = document.editing("changed")

        #expect(edited.isDirty)
        #expect(edited.text == "changed")
        #expect(document.text == "saved")
    }

    @Test func editingBackToSavedTextIsClean() {
        #expect(!document.editing("changed").editing("saved").isDirty)
    }

    @Test func movingKeepsTextAndUnsavedChanges() {
        let moved = document.editing("changed").moving(to: URL(filePath: "/tmp/renamed.md"))

        #expect(moved.url.lastPathComponent == "renamed.md")
        #expect(moved.text == "changed")
        #expect(moved.isDirty)
    }

    @Test func markingSavedClearsDirtyState() {
        let saved = document.editing("changed").markingSaved()

        #expect(!saved.isDirty)
        #expect(saved.text == "changed")
    }
}
