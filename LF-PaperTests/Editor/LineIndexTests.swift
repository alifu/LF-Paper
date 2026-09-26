//
//  LineIndexTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

struct LineIndexTests {

    @Test func emptyTextHasOneLine() {
        let index = LineIndex(text: "")

        #expect(index.lineStarts == [0])
        #expect(index.lineCount == 1)
    }

    @Test func recordsTheStartOfEveryLine() {
        #expect(LineIndex(text: "ab\ncd\ne").lineStarts == [0, 3, 6])
    }

    @Test func trailingNewlineStartsAnEmptyLastLine() {
        #expect(LineIndex(text: "a\n").lineStarts == [0, 2])
    }

    @Test func windowsLineEndingsCountOnce() {
        #expect(LineIndex(text: "a\r\nb").lineStarts == [0, 3])
    }

    @Test func lineNumberIsOneBasedAndIncludesTheNewline() {
        let index = LineIndex(text: "ab\ncd\ne")

        #expect(index.lineNumber(at: 0) == 1)
        #expect(index.lineNumber(at: 2) == 1) // the "\n" ending line 1
        #expect(index.lineNumber(at: 3) == 2)
        #expect(index.lineNumber(at: 6) == 3)
        #expect(index.lineNumber(at: 7) == 3) // end of text
    }
}
