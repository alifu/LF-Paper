//
//  CompareModelTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

@MainActor
struct CompareModelTests {
    private let model = CompareModel()

    private func settle() async {
        await model.comparisonTask?.value
    }

    private var result: JSONComparison.Result? {
        guard case .compared(let result) = model.outcome else { return nil }
        return result
    }

    @Test func comparesOnceBothSidesAreSet() async throws {
        model.setSide(.left, title: "old.json", text: #"{"a":1}"#)
        await settle()
        #expect(model.outcome == .incomplete)

        model.setSide(.right, title: "new.json", text: #"{"a":2}"#)
        await settle()

        #expect(try #require(result).differences.map(\.description) == ["~ $.a: 1 → 2"])
    }

    @Test func swappingSidesSwapsTitlesAndDirection() async throws {
        model.setSide(.left, title: "old.json", text: "[1]")
        model.setSide(.right, title: "new.json", text: "[1,2]")

        model.swapSides()
        await settle()

        #expect(model.left?.title == "new.json")
        #expect(model.right?.title == "old.json")
        #expect(try #require(result).differences.map(\.description) == ["- $[1]: 2"])
    }

    @Test func clearingASideStopsComparing() async {
        model.setSide(.left, title: "a", text: "[1]")
        model.setSide(.right, title: "b", text: "[2]")
        await settle()

        model.clearSide(.right)
        await settle()

        #expect(model.outcome == .incomplete)
    }

    @Test func changingOptionsComparesAgain() async throws {
        model.setSide(.left, title: "a", text: #"{"a":1,"b":2}"#)
        model.setSide(.right, title: "b", text: #"{"b":2,"a":1}"#)
        await settle()
        #expect(try #require(result).changeStarts.isEmpty)

        model.ignoresKeyOrder = false
        await settle()

        #expect(try #require(result).changeStarts.isEmpty == false)
    }

    @Test func arrayMatchKeyIsTrimmedAndBlankMeansByIndex() async throws {
        model.setSide(.left, title: "a", text: #"[{"id":1},{"id":2}]"#)
        model.setSide(.right, title: "b", text: #"[{"id":2},{"id":1}]"#)
        model.arrayMatchKey = "  "
        await settle()
        #expect(try #require(result).differences.count == 2)

        model.arrayMatchKey = " id "
        await settle()

        #expect(try #require(result).differences.isEmpty)
    }

    // MARK: Navigation

    private func loadTwoChanges() async {
        model.setSide(.left, title: "a", text: "[1,2,3,4,5]")
        model.setSide(.right, title: "b", text: "[1,20,3,40,5]")
        await settle()
    }

    @Test func nextAndPreviousStepThroughChangesAndWrap() async {
        await loadTwoChanges()
        #expect(model.changeCount == 2)
        #expect(model.focusedChange == nil)

        model.focusNextChange()
        #expect(model.focusedChange == 0)
        model.focusNextChange()
        #expect(model.focusedChange == 1)
        model.focusNextChange()
        #expect(model.focusedChange == 0)
        model.focusPreviousChange()
        #expect(model.focusedChange == 1)
    }

    @Test func previousFromNothingGoesToTheLastChange() async {
        await loadTwoChanges()

        model.focusPreviousChange()

        #expect(model.focusedChange == 1)
    }

    @Test func aNewComparisonClearsTheFocus() async {
        await loadTwoChanges()
        model.focusNextChange()

        model.setSide(.right, title: "b", text: "[1,2,3,4,6]")
        await settle()

        #expect(model.focusedChange == nil)
    }

    // MARK: Loading files

    @Test func loadsASideFromAFile() async throws {
        let folder = try TemporaryDirectory()
        let file = try folder.makeFile("left.json", contents: "[1]")

        model.loadSide(.left, from: file)

        #expect(model.left == CompareModel.Side(title: "left.json", text: "[1]"))
        #expect(model.presentedError == nil)
    }

    @Test func aMissingFileIsReported() throws {
        let missing = try TemporaryDirectory().url.appending(path: "gone.json")

        model.loadSide(.left, from: missing)

        #expect(model.left == nil)
        #expect(model.presentedError == .fileNotFound(missing))
    }
}
