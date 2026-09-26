//
//  WorkspaceModelJSONTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

@MainActor
final class WorkspaceModelJSONTests {
    private let suiteName = "LFPaperTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let folder: TemporaryDirectory

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        folder = try TemporaryDirectory()
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    private func model(opening name: String, contents: String) throws -> WorkspaceModel {
        try folder.makeFile(name, contents: contents)
        let model = WorkspaceModel(
            bookmarkStore: BookmarkStore(defaults: defaults),
            recentFolders: RecentFolders(defaults: defaults),
            watchesFileSystem: false
        )
        model.openFolder(folder.url)
        model.selection = try #require(model.children(of: folder.url).first { $0.name == name }).url
        return model
    }

    // MARK: Formatting

    @Test func formatPrettyPrintsTheDocumentAsAnUnsavedEdit() throws {
        let model = try model(opening: "data.json", contents: "{\"b\":1,\"a\":[1,2]}\n")

        model.formatJSON()

        #expect(model.document?.text == "{\n  \"b\": 1,\n  \"a\": [\n    1,\n    2\n  ]\n}\n")
        #expect(model.document?.isDirty == true)
    }

    @Test func formatCanSortKeysAndUseTabs() throws {
        let model = try model(opening: "data.json", contents: #"{"b":1,"a":2}"#)

        model.formatJSON(indentation: .tab, sortsKeys: true)

        #expect(model.document?.text == "{\n\t\"a\": 2,\n\t\"b\": 1\n}")
    }

    @Test func minifyRemovesWhitespaceButKeepsTheFinalNewline() throws {
        let model = try model(opening: "data.json", contents: "{\n  \"a\": [1, 2]\n}\n")

        model.minifyJSON()

        #expect(model.document?.text == "{\"a\":[1,2]}\n")
    }

    @Test func formattingInvalidJSONRevealsTheErrorAndLeavesTheTextAlone() throws {
        let model = try model(opening: "data.json", contents: #"{"a":}"#)

        model.formatJSON()

        #expect(model.document?.text == #"{"a":}"#)
        #expect(model.revealRequest?.range.location == 5)
        #expect(model.revealRequest?.focusesEditor == true)
    }

    // MARK: Revealing

    @Test func revealingATreeValueSelectsItsSourceWithoutStealingFocus() async throws {
        let text = #"{"a": [1, 2]}"#
        let model = try model(opening: "data.json", contents: text)
        await model.json.analysisTask?.value

        model.revealJSONValue(at: JSONPath.root.appending(.key("a")))

        let request = try #require(model.revealRequest)
        #expect((text as NSString).substring(with: request.range) == "[1, 2]")
        #expect(!request.focusesEditor)
    }

    @Test func everyRevealIsANewRequest() throws {
        let model = try model(opening: "data.json", contents: "[1]")

        model.reveal(NSRange(location: 0, length: 1), focusesEditor: false)
        let first = model.revealRequest
        model.reveal(NSRange(location: 0, length: 1), focusesEditor: false)

        #expect(model.revealRequest?.id != first?.id)
    }

    // MARK: Session

    @Test func theJSONSessionFollowsTheOpenDocument() async throws {
        let model = try model(opening: "data.json", contents: "[1]")
        await model.json.analysisTask?.value
        #expect(model.json.status == .valid)
        #expect(model.isJSONDocument)

        try folder.makeFile("notes.md", contents: "# Notes")
        model.reloadAll()
        model.selection = try #require(model.children(of: folder.url).first { $0.name == "notes.md" }).url

        #expect(model.json.status == .inactive)
        #expect(!model.isJSONDocument)
    }
}
