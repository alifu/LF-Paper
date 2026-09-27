//
//  WorkspaceModelSwiftModelTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

/// JSON › Generate Swift Model: the sheet's options, its live preview, and opening the result in a new tab.
@MainActor
struct WorkspaceModelSwiftModelTests {
    private let workspace: TestWorkspace

    init() throws {
        workspace = try TestWorkspace(files: [
            "users.json": #"[{"id": 1, "first_name": "Ada"}, {"id": 2, "first_name": "Grace"}]"#,
            "broken.json": #"{"a": "#,
            "number.json": "42",
            "notes.md": "# Notes",
        ])
    }

    private var model: WorkspaceModel { workspace.model }

    private func openGenerator(for file: String) async throws -> SwiftModelSession {
        try await workspace.openJSON(file)
        model.showSwiftModelGenerator()
        return try #require(model.swiftModelGenerator)
    }

    @Test func onlyValidJSONDocumentsCanGenerateAModel() async throws {
        #expect(!model.canGenerateSwiftModel) // nothing open
        try workspace.open("notes.md")
        #expect(!model.canGenerateSwiftModel)
        try await workspace.openJSON("broken.json")
        #expect(!model.canGenerateSwiftModel)
        try await workspace.openJSON("users.json")
        #expect(model.canGenerateSwiftModel)
    }

    @Test func thePreviewUsesTheFileNameForTheRootType() async throws {
        let session = try await openGenerator(for: "users.json")

        #expect(session.options.rootName == "User")
        #expect(session.error == nil)
        #expect(session.fileName == "User.swift")
        let source = try #require(session.source)
        #expect(source.contains("struct User: Codable {"))
        #expect(source.contains("case firstName = \"first_name\""))
        #expect(source.contains("decode([User].self"))
    }

    @Test func changingAnOptionUpdatesThePreview() async throws {
        let session = try await openGenerator(for: "users.json")

        session.options.kind = .classes
        session.options.rootName = "Person"

        #expect(session.source?.contains("final class Person: Codable {") == true)
        #expect(session.fileName == "Person.swift")
    }

    @Test func invalidJSONIsExplainedInsteadOfOpeningTheSheet() async throws {
        try await workspace.openJSON("broken.json")

        model.showSwiftModelGenerator()

        #expect(model.swiftModelGenerator == nil)
        #expect(model.presentedError?.errorDescription?.isEmpty == false)
    }

    @Test func aTopLevelThatIsntAnObjectIsExplainedInTheSheet() async throws {
        let session = try await openGenerator(for: "number.json")

        #expect(session.source == nil)
        #expect(session.error == .topLevelNotObject)
        model.openGeneratedSwiftModel()
        #expect(model.tabs.count == 1) // nothing opened
    }

    @Test func openingTheResultAddsAnUnsavedTabNextToTheJSON() async throws {
        let session = try await openGenerator(for: "users.json")
        let source = try #require(session.source)

        model.openGeneratedSwiftModel()

        let tab = try #require(model.document)
        #expect(tab.url == workspace.folder.url.appending(path: "User.swift"))
        #expect(tab.isNew)
        #expect(tab.text == source)
        #expect(model.swiftModelGenerator == nil)
        #expect(!FileManager.default.fileExists(atPath: tab.url.path)) // nothing written yet

        #expect(model.save())
        #expect(try String(contentsOf: tab.url, encoding: .utf8) == source)
        #expect(model.children(of: workspace.folder.url).contains { $0.name == "User.swift" && $0.kind == .swift })
    }

    @Test func anExistingFileIsntReplaced() async throws {
        try workspace.folder.makeFile("User.swift", contents: "// mine")
        model.reloadAll()
        _ = try await openGenerator(for: "users.json")

        model.openGeneratedSwiftModel()

        #expect(model.document?.url.lastPathComponent == "User 2.swift")
    }

    @Test func cancellingClosesTheSheet() async throws {
        _ = try await openGenerator(for: "users.json")

        model.swiftModelGenerator = nil

        #expect(model.tabs.count == 1)
    }

    @Test func conformancesThatDontApplyAreUnavailable() {
        var options = SwiftModelOptions()
        #expect(SwiftModelOptions.Conformance.allCases.allSatisfy(options.allows))

        options.kind = .classes
        options.usesVar = true
        #expect(!options.allows(.sendable))
        #expect(options.allows(.hashable))

        options.kind = .dictionary
        #expect(options.allows(.identifiable))
        #expect(!options.allows(.hashable))
        #expect(!options.allows(.sendable))
    }
}
