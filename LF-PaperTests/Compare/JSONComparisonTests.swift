//
//  JSONComparisonTests.swift
//  LF-PaperTests
//

import Testing
@testable import LF_Paper

struct JSONComparisonTests {
    private func compared(_ left: String?, _ right: String?, options: JSONComparison.Options = .init()) -> JSONComparison.Result? {
        guard case .compared(let result) = JSONComparison.run(left: left, right: right, options: options) else { return nil }
        return result
    }

    @Test func nothingToCompareUntilBothSidesAreSet() {
        #expect(JSONComparison.run(left: "{}", right: nil, options: .init()) == .incomplete)
        #expect(JSONComparison.run(left: nil, right: nil, options: .init()) == .incomplete)
    }

    @Test func anInvalidSideIsReportedWithItsError() {
        guard case .invalid(let side, let error) = JSONComparison.run(left: "{}", right: "{\n  \"a\": }", options: .init()) else {
            Issue.record("expected the right side to be invalid")
            return
        }
        #expect(side == .right)
        #expect(error.line == 2)
    }

    @Test func theLeftSideIsCheckedFirst() {
        guard case .invalid(let side, _) = JSONComparison.run(left: "[", right: "{", options: .init()) else {
            Issue.record("expected an invalid side")
            return
        }
        #expect(side == .left)
    }

    @Test func comparesStructureAndText() throws {
        let result = try #require(compared(#"{"a":1,"b":2}"#, #"{"a":1,"b":3}"#))

        #expect(result.differences.map(\.description) == ["~ $.b: 2 → 3"])
        #expect(result.rows.filter(\.isChange).map { "\($0.left?.text ?? "") → \($0.right?.text ?? "")" } == [#"  "b": 2 →   "b": 3"#])
        #expect(result.changeStarts.count == 1)
    }

    @Test func whitespaceNeverShowsAsAChange() throws {
        let result = try #require(compared("{\"a\":[1,2]}", "{\n    \"a\" : [ 1, 2 ]\n}\n"))

        #expect(result.differences.isEmpty)
        #expect(!result.rows.contains { $0.isChange })
    }

    @Test func keyOrderIsIgnoredInTheTextWhenAsked() throws {
        let ignoring = try #require(compared(#"{"a":1,"b":2}"#, #"{"b":2,"a":1}"#, options: .init(ignoresKeyOrder: true)))
        let keeping = try #require(compared(#"{"a":1,"b":2}"#, #"{"b":2,"a":1}"#, options: .init(ignoresKeyOrder: false)))

        #expect(!ignoring.rows.contains { $0.isChange })
        #expect(keeping.rows.contains { $0.isChange })
        #expect(keeping.differences.isEmpty) // the structure is still the same
    }

    @Test func arraysCanBeMatchedByKey() throws {
        let options = JSONComparison.Options(arrayMatchKey: "id")
        let result = try #require(compared(#"[{"id":1},{"id":2}]"#, #"[{"id":2},{"id":1}]"#, options: options))

        #expect(result.differences.isEmpty)
    }
}
