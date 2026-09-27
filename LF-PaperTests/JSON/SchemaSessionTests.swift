//
//  SchemaSessionTests.swift
//  LF-PaperTests
//

import AppKit
import SwiftUI
import Testing
@testable import LF_Paper

/// Which schema a document uses, loading it, and the problems with their lines.
@MainActor
struct SchemaSessionTests {
    private static let schema = #"""
        {"type": "object", "required": ["name"],
         "properties": {"name": {"type": "string"}, "age": {"type": "integer", "minimum": 0}}}
        """#

    // MARK: Choosing the schema

    private func source(_ document: String, choice: SchemaChoice = .automatic) throws -> SchemaSource {
        let value = try JSONParser.parse(document).value
        return SchemaSource.resolve(choice: choice, document: value, documentURL: URL(filePath: "/project/data/user.json"))
    }

    @Test func theDocumentsSchemaIsFoundNextToIt() throws {
        #expect(try source(#"{"$schema": "../schemas/user.schema.json"}"#) == .file(URL(filePath: "/project/schemas/user.schema.json")))
        #expect(try source(#"{"$schema": "file:///tmp/s.json"}"#) == .file(URL(filePath: "/tmp/s.json")))
    }

    @Test func webSchemasAreNotFetched() throws {
        #expect(try source(#"{"$schema": "https://json-schema.org/draft/2020-12/schema"}"#) == .remote("https://json-schema.org/draft/2020-12/schema"))
    }

    @Test func aChosenFileWinsAndChecksCanBeTurnedOff() throws {
        let chosen = URL(filePath: "/project/other.json")
        #expect(try source(#"{"$schema": "x.json"}"#, choice: .file(chosen)) == .file(chosen))
        #expect(try source(#"{"$schema": "x.json"}"#, choice: .off) == .off)
        #expect(try source(#"{"name": "no schema"}"#) == .none)
        #expect(try source("[1, 2]") == .none)
    }

    // MARK: Checking

    private func check(_ document: String, schemaText: String? = schema, schemaReference: String = "user.schema.json") async throws -> SchemaState {
        let folder = try TemporaryDirectory()
        if let schemaText {
            try folder.makeFile(schemaReference, contents: schemaText)
        }
        let text = document.replacingOccurrences(of: "SCHEMA", with: schemaReference)
        let parsed = try JSONParser.parse(text, recordsSourceRanges: true)
        let session = SchemaSession()
        await session.check(document: parsed, text: text, documentURL: folder.url.appending(path: "user.json"))
        return session.state
    }

    @Test func aMatchingDocumentHasNoProblems() async throws {
        let state = try await check(#"{"$schema": "SCHEMA", "name": "Ada"}"#)

        #expect(state == .checked(schemaName: "user.schema.json", issues: []))
    }

    @Test func problemsCarryTheirPathLineAndRange() async throws {
        let document = "{\n  \"$schema\": \"SCHEMA\",\n  \"age\": -1\n}"

        guard case .checked(_, let issues) = try await check(document) else {
            Issue.record("expected a check")
            return
        }
        #expect(issues.map(\.message) == ["“name” is required", "Must be at least 0"])
        #expect(issues.map(\.line) == [1, 3])
        #expect(issues[1].path.description == "$.age")
        #expect(issues[1].range == NSRange(location: 44, length: 2)) // the "-1"
    }

    @Test func aMissingSchemaFileIsExplained() async throws {
        let state = try await check(#"{"$schema": "SCHEMA"}"#, schemaText: nil)

        guard case .unreadable(let name, let reason) = state else {
            Issue.record("expected unreadable, got \(state)")
            return
        }
        #expect(name == "user.schema.json")
        #expect(reason.contains("could not be found"))
    }

    @Test func aSchemaThatIsNotJSONIsExplained() async throws {
        let state = try await check(#"{"$schema": "SCHEMA"}"#, schemaText: "{ not json")

        guard case .unreadable(_, let reason) = state else {
            Issue.record("expected unreadable, got \(state)")
            return
        }
        #expect(reason.hasPrefix("Line 1"))
    }

    @Test func webSchemasAreReportedNotLoaded() async throws {
        let state = try await check(#"{"$schema": "https://example.com/s.json"}"#, schemaText: nil)

        #expect(state == .remote("https://example.com/s.json"))
    }

    // MARK: From the workspace

    @Test func theWorkspaceChecksTheOpenFileAndRevealsAProblem() async throws {
        let workspace = try TestWorkspace(files: [
            "user.json": "{\n  \"$schema\": \"user.schema.json\",\n  \"age\": -1\n}",
            "user.schema.json": Self.schema,
        ])
        try await workspace.openJSON("user.json")

        await workspace.model.checkSchema()

        guard case .checked(_, let issues) = workspace.model.schema.state else {
            Issue.record("expected a check, got \(workspace.model.schema.state)")
            return
        }
        #expect(issues.count == 2)
        workspace.model.reveal(issues[1])
        #expect(workspace.model.revealRequest?.range == issues[1].range)
        #expect(workspace.model.revealRequest?.focusesEditor == true)
    }

    @Test func choicesAreRememberedPerDocument() throws {
        let session = SchemaSession()
        let a = URL(filePath: "/p/a.json")
        let b = URL(filePath: "/p/b.json")

        session.setChoice(.off, for: a)

        #expect(session.choice(for: a) == .off)
        #expect(session.choice(for: b) == .automatic)
    }
}

/// Renders the schema panel with problems, in dark and light mode.
@MainActor
struct SchemaPanelRenderingTests {
    private static let size = NSSize(width: 360, height: 220)

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func listsProblemsWithTheirLines(appearance: NSAppearance.Name) async throws {
        let workspace = try TestWorkspace(files: [
            "user.json": "{\n  \"$schema\": \"user.schema.json\",\n  \"age\": -1\n}",
            "user.schema.json": #"{"required": ["name"], "properties": {"age": {"minimum": 0}}}"#,
        ])
        try await workspace.openJSON("user.json")
        await workspace.model.checkSchema()

        let view = SchemaPanel(model: workspace.model).background(Color(nsColor: .windowBackgroundColor))
        let bitmap = try OffscreenRenderer.render(view, size: Self.size, appearance: appearance)
        try OffscreenRenderer.attach(bitmap, named: "schema-panel-\(appearance.rawValue).png")

        #expect(OffscreenRenderer.pixelsStandingOut(in: bitmap) > 200, "the status and problems should be visible")
    }
}
