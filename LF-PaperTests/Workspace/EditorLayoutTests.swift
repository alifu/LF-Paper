//
//  EditorLayoutTests.swift
//  LF-PaperTests
//

import Testing
@testable import LF_Paper

struct EditorLayoutTests {

    @Test func togglingPreviewSwitchesBetweenEditorOnlyAndSplit() {
        #expect(EditorLayout.split.togglingPreview() == .editor)
        #expect(EditorLayout.editor.togglingPreview() == .split)
    }

    @Test func togglingPreviewFromPreviewOnlyBringsTheEditorBack() {
        #expect(EditorLayout.preview.togglingPreview() == .editor)
    }

    @Test func showsPanesForEachLayout() {
        #expect(EditorLayout.editor.showsEditor && !EditorLayout.editor.showsPreview)
        #expect(EditorLayout.split.showsEditor && EditorLayout.split.showsPreview)
        #expect(!EditorLayout.preview.showsEditor && EditorLayout.preview.showsPreview)
    }
}
