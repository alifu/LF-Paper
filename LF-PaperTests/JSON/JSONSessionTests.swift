//
//  JSONSessionTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

@MainActor
struct JSONSessionTests {
    private let session = JSONSession()

    private func document(_ text: String, name: String = "data.json") -> OpenDocument {
        OpenDocument(url: URL(filePath: "/tmp/\(name)"), text: text)
    }

    private func analyze(_ document: OpenDocument?) async {
        session.documentDidChange(document)
        await session.analysisTask?.value
    }

    @Test func validJSONProducesATreeAndSourceRanges() async {
        await analyze(document(#"{"a": 1}"#))

        #expect(session.status == .valid)
        #expect(session.tree?.summary == "1 key")
        #expect(session.sourceRanges[JSONPath.root.appending(.key("a"))] == NSRange(location: 6, length: 1))
    }

    @Test func invalidJSONReportsTheErrorAndKeepsTheLastValidTree() async throws {
        let valid = document(#"{"a": 1}"#)
        await analyze(valid)

        await analyze(valid.editing(#"{"a": }"#))

        guard case .invalid(let error) = session.status else {
            Issue.record("expected an error, got \(session.status)")
            return
        }
        #expect(error.column == 7)
        #expect(session.tree?.summary == "1 key")
    }

    @Test func versionIncreasesWithEachSuccessfulParse() async {
        let first = document("[1]")
        await analyze(first)
        let version = session.version

        await analyze(first.editing("[1, 2]"))

        #expect(session.version > version)
    }

    @Test func anotherDocumentStartsWithoutTheOldTree() async {
        await analyze(document("[1]"))

        await analyze(document("{", name: "other.json"))

        #expect(session.tree == nil)
    }

    @Test func nonJSONDocumentsAreIgnored() async {
        await analyze(document("# Title", name: "notes.md"))

        #expect(session.status == .inactive)
        #expect(session.tree == nil)
    }

    @Test func closingTheDocumentClearsEverything() async {
        await analyze(document("[1]"))

        await analyze(nil)

        #expect(session.status == .inactive)
        #expect(session.sourceRanges.isEmpty)
    }
}
