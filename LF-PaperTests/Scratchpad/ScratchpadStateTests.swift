//
//  ScratchpadStateTests.swift
//  LF-PaperTests
//

import AppKit
import Testing
@testable import LF_Paper

/// The scratchpad's own state, apart from how the workspace shows it.
@MainActor
struct ScratchpadStateTests {
    @Test func startsHiddenAndEmpty() {
        let scratchpad = ScratchpadState()

        #expect(!scratchpad.isActive)
        #expect(scratchpad.text.isEmpty)
        #expect(scratchpad.copyID == nil)
    }

    @Test func keepsTheLatestTextAndClears() {
        let scratchpad = ScratchpadState()

        scratchpad.update("notes")
        #expect(scratchpad.text == "notes")

        scratchpad.clear()
        #expect(scratchpad.text.isEmpty)
    }

    @Test func eachCopyPutsTheTextOnThePasteboardWithANewID() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("LFPaperTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let scratchpad = ScratchpadState()
        scratchpad.update("copy me")

        scratchpad.copy(to: pasteboard)
        let firstID = try #require(scratchpad.copyID)
        scratchpad.copy(to: pasteboard)

        #expect(pasteboard.string(forType: .string) == "copy me")
        #expect(scratchpad.copyID != firstID)
    }

    @Test func eachScratchpadHasItsOwnStableID() {
        let scratchpad = ScratchpadState()

        #expect(scratchpad.id == scratchpad.id)
        #expect(ScratchpadState().id != scratchpad.id)
    }
}
