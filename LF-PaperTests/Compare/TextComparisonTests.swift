//
//  TextComparisonTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

/// Comparing any text (such as Markdown) line by line, and asking for a comparison from the workspace.
@MainActor
struct TextComparisonTests {
    @Test func comparesTheLinesAsWritten() throws {
        let outcome = TextComparison.run(left: "# Title\nold line\n", right: "# Title\nnew line\n")

        guard case .compared(let result) = outcome else {
            Issue.record("expected a comparison, got \(outcome)")
            return
        }
        #expect(result.differences.isEmpty) // no structure to compare in plain text
        #expect(result.changeStarts.count == 1)
        #expect(result.rows.map { $0.left?.text } == ["# Title", "old line"])
        #expect(result.rows.map { $0.right?.text } == ["# Title", "new line"])
    }

    @Test func needsBothSides() {
        #expect(TextComparison.run(left: nil, right: "x") == .incomplete)
    }

    @Test func theCompareWindowComparesTextAsWrittenInTextMode() async throws {
        let compare = CompareModel()

        compare.show(ComparisonRequest(
            left: CompareModel.Side(title: "notes.md — Saved", text: "not { json"),
            right: CompareModel.Side(title: "notes.md — Edited", text: "not { json at all"),
            kind: .text
        ))
        await compare.comparisonTask?.value

        #expect(compare.contentKind == .text)
        #expect(compare.changeCount == 1)
    }

    @Test func choosingASideByHandGoesBackToJSON() async throws {
        let compare = CompareModel()
        compare.show(ComparisonRequest(left: .init(title: "a", text: "x"), right: .init(title: "b", text: "y"), kind: .text))

        compare.setSide(.left, title: "Pasted", text: "{}")

        #expect(compare.contentKind == .json)
    }

    // MARK: Compare with saved version

    @Test func thereIsNothingToCompareWithoutUnsavedChanges() throws {
        let workspace = try TestWorkspace(files: ["notes.md": "# Notes\n"])
        try workspace.open("notes.md")

        #expect(workspace.model.comparisonWithSavedVersion() == nil)
    }

    @Test func comparesTheSavedTextWithTheEdits() throws {
        let workspace = try TestWorkspace(files: ["notes.md": "# Notes\n", "data.json": "{}"])
        try workspace.open("notes.md")
        workspace.model.updateDocumentText("# Notes\nMore.\n")

        let request = try #require(workspace.model.comparisonWithSavedVersion())

        #expect(request.left == CompareModel.Side(title: "notes.md — Saved", text: "# Notes\n"))
        #expect(request.right == CompareModel.Side(title: "notes.md — Edited", text: "# Notes\nMore.\n"))
        #expect(request.kind == .text)

        try workspace.open("data.json")
        workspace.model.updateDocumentText(#"{"a": 1}"#)
        #expect(workspace.model.comparisonWithSavedVersion()?.kind == .json)
    }
}
