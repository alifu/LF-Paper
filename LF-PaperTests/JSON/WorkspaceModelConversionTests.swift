//
//  WorkspaceModelConversionTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

/// Convert in the JSON menu: the result opens in a new, unsaved tab next to the file,
/// so nothing is overwritten until it's saved.
@MainActor
struct WorkspaceModelConversionTests {
    private let workspace: TestWorkspace

    init() throws {
        workspace = try TestWorkspace(files: [
            "people.json": #"[{"name": "Ada", "age": 36}, {"name": "Grace", "age": 45}]"#,
            "config.yaml": "name: app\nport: 8080\n",
            "table.csv": "id,label\n1,one\n",
            "bad.json": "{ nope",
        ])
    }

    private var model: WorkspaceModel { workspace.model }

    private func onDisk(_ name: String) -> Bool {
        workspace.folder.exists(name)
    }

    @Test func yamlAndCSVFilesAreListedAndEditable() throws {
        let names = model.children(of: workspace.folder.url).map(\.name)
        #expect(names.contains("config.yaml"))
        #expect(names.contains("table.csv"))
        #expect(FileKind(fileExtension: "yml") == .yaml)
        #expect(FileKind(fileExtension: "CSV") == .csv)

        try workspace.open("config.yaml")
        #expect(model.document?.text == "name: app\nport: 8080\n")
    }

    @Test func convertingToYAMLOpensANewUnsavedTab() throws {
        try workspace.open("people.json")

        model.convertToYAML()

        let document = try #require(model.document)
        #expect(document.url.lastPathComponent == "people.yaml")
        #expect(document.isNew)
        #expect(document.text.hasPrefix("- name: Ada\n"))
        #expect(model.hasUnsavedChanges(inTab: document.id))
        #expect(model.tabs.count == 2)
        #expect(!onDisk("people.yaml"), "nothing is written until it's saved")
    }

    @Test func theNewFileGetsAFreeName() throws {
        try workspace.folder.makeFile("people.csv", contents: "x\n")
        model.reloadAll()
        try workspace.open("people.json")

        model.convertToCSV()
        #expect(model.document?.url.lastPathComponent == "people 2.csv")

        try workspace.open("people.json")
        model.convertToCSV() // "people 2.csv" is taken by the open tab now
        #expect(model.document?.url.lastPathComponent == "people 3.csv")
    }

    @Test func savingCreatesTheFileAndListsIt() throws {
        try workspace.open("people.json")
        model.convertToCSV()

        #expect(model.save())

        #expect(try workspace.folder.contents(of: "people.csv") == "name,age\r\nAda,36\r\nGrace,45\r\n")
        #expect(model.document?.isNew == false)
        #expect(!model.hasUnsavedChanges)
        #expect(model.children(of: workspace.folder.url).map(\.name).contains("people.csv"))
    }

    @Test func notSavingLeavesNoFile() throws {
        try workspace.open("people.json")
        model.convertToYAML()
        let id = try #require(model.document?.id)

        model.closeTab(id)
        model.resolvePendingAction(.discard)

        #expect(!onDisk("people.yaml"))
        #expect(model.tabs.count == 1)
    }

    @Test func discardingEverythingClosesNewTabs() throws {
        try workspace.open("people.json")
        model.convertToYAML()

        model.discardUnsavedChanges()

        #expect(model.tabs.map(\.url.lastPathComponent) == ["people.json"])
    }

    @Test func diskChangesAndAutosaveLeaveNewTabsAlone() async throws {
        model.autosaveDelay = .milliseconds(10)
        try workspace.open("people.json")
        model.convertToYAML()
        let id = try #require(model.document?.id)

        model.reloadAll()
        model.updateDocumentText(model.document!.text + "# note\n")
        await model.autosaveTask?.value

        #expect(model.tabs.contains { $0.id == id })
        #expect(!model.isDocumentMissingOnDisk)
        #expect(!onDisk("people.yaml"), "a new file is only created by Save")
    }

    @Test func yamlAndCSVConvertToFormattedJSON() throws {
        try workspace.open("config.yaml")
        model.convertToJSON(indentation: .spaces(2))
        #expect(model.document?.url.lastPathComponent == "config.json")
        #expect(model.document?.text == "{\n  \"name\": \"app\",\n  \"port\": 8080\n}\n")

        try workspace.open("table.csv")
        model.convertToJSON(indentation: .spaces(2))
        #expect(model.document?.url.lastPathComponent == "table.json")
        #expect(model.document?.text.contains("\"label\": \"one\"") == true)
    }

    @Test func problemsAreShownInsteadOfOpeningATab() throws {
        try workspace.open("bad.json")
        model.convertToYAML()
        #expect(model.presentedError?.errorDescription?.hasPrefix("Fix the JSON first") == true)

        model.presentedError = nil
        try workspace.open("people.json")
        model.updateDocumentText(#"{"not": "a list"}"#)
        model.convertToCSV()
        #expect(model.presentedError == .conversionFailed("Only a list of objects can become CSV; this is a single value."))
        #expect(model.tabs.count == 2)
    }

    @Test func whatCanBeConvertedDependsOnTheFile() throws {
        try workspace.open("people.json")
        #expect(model.canConvertFromJSON)
        #expect(!model.canConvertToJSON)

        try workspace.open("config.yaml")
        #expect(!model.canConvertFromJSON)
        #expect(model.canConvertToJSON)
    }
}
