//
//  LongLineTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

/// Files with a very long line (usually minified JSON) are edited as plain text,
/// and JSON ones get an offer to format them.
@MainActor
struct LongLineTests {
    private static let threshold = LongLines.threshold
    private static let minifiedJSON = "[" + String(repeating: "1,", count: threshold / 2) + "1]"

    @Test func detectsALineAtOrOverTheThreshold() {
        #expect(!LongLines.containsLongLine("short\nlines\n"))
        #expect(!LongLines.containsLongLine(String(repeating: "a", count: Self.threshold - 1)))
        #expect(LongLines.containsLongLine(String(repeating: "a", count: Self.threshold)))
        #expect(LongLines.containsLongLine("first\n" + String(repeating: "a", count: Self.threshold) + "\nlast"))
        #expect(!LongLines.containsLongLine(String(repeating: "abc\r\n", count: Self.threshold / 4)))
    }

    @Test func aMinifiedJSONFileIsEditedAsPlainTextAndOffersFormatting() throws {
        let workspace = try TestWorkspace(files: ["big.json": Self.minifiedJSON, "small.json": #"{"a": 1}"#])

        try workspace.open("big.json")
        #expect(workspace.model.editsAsPlainText)
        #expect(workspace.model.offersFormatting)

        try workspace.open("small.json")
        #expect(!workspace.model.editsAsPlainText)
        #expect(!workspace.model.offersFormatting)
    }

    @Test func formattingEndsTheOfferAndHighlightingComesBack() throws {
        let workspace = try TestWorkspace(files: ["big.json": Self.minifiedJSON])
        try workspace.open("big.json")

        workspace.model.formatJSON()

        #expect(!workspace.model.offersFormatting)
        #expect(!workspace.model.editsAsPlainText)
    }

    @Test func notNowHidesTheOfferButKeepsPlainText() throws {
        let workspace = try TestWorkspace(files: ["big.json": Self.minifiedJSON])
        try workspace.open("big.json")

        workspace.model.declineFormatting()

        #expect(!workspace.model.offersFormatting)
        #expect(workspace.model.editsAsPlainText)
    }

    @Test func longMarkdownLinesAreEditedAsPlainTextWithoutAnOffer() throws {
        let workspace = try TestWorkspace(files: ["notes.md": String(repeating: "word ", count: Self.threshold / 5)])

        try workspace.open("notes.md")

        #expect(workspace.model.editsAsPlainText)
        #expect(!workspace.model.offersFormatting)
    }

    @Test func longLinesAlwaysWrapBecauseScrollingAMegabyteLineIsSlow() throws {
        let workspace = try TestWorkspace(files: ["big.json": Self.minifiedJSON, "small.json": #"{"a": 1}"#])

        try workspace.open("big.json")
        #expect(workspace.model.wrapsLines(preference: false))

        try workspace.open("small.json")
        #expect(!workspace.model.wrapsLines(preference: false))
        #expect(workspace.model.wrapsLines(preference: true))

        workspace.model.showScratchpad()
        #expect(workspace.model.wrapsLines(preference: false)) // prose always wraps
    }

    @Test func theScratchpadIsNeverAffected() throws {
        let workspace = try TestWorkspace(files: ["big.json": Self.minifiedJSON])
        try workspace.open("big.json")

        workspace.model.showScratchpad()

        #expect(!workspace.model.editsAsPlainText)
        #expect(!workspace.model.offersFormatting)
    }
}
