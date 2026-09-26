//
//  JSONDiffTests.swift
//  LF-PaperTests
//

import Testing
@testable import LF_Paper

struct JSONDiffTests {
    private func diff(_ old: String, _ new: String, matchingArraysBy key: String? = nil) throws -> [String] {
        let oldValue = try JSONParser.parse(old).value
        let newValue = try JSONParser.parse(new).value
        return JSONDiff.differences(from: oldValue, to: newValue, arrayMatchKey: key).map(\.description)
    }

    // MARK: Basics

    @Test func identicalDocumentsHaveNoDifferences() throws {
        #expect(try diff(#"{"a":[1,{"b":null}]}"#, #"{"a":[1,{"b":null}]}"#).isEmpty)
    }

    @Test func aChangedRootScalar() throws {
        #expect(try diff("1", "2") == ["~ $: 1 → 2"])
    }

    @Test func objectMembersChangedRemovedAndAdded() throws {
        let differences = try diff(#"{"a":1,"b":2,"c":3}"#, #"{"a":1,"b":20,"d":4}"#)

        #expect(differences == ["~ $.b: 2 → 20", "- $.c: 3", "+ $.d: 4"])
    }

    @Test func keyOrderAloneIsNotADifference() throws {
        #expect(try diff(#"{"a":1,"b":2}"#, #"{"b":2,"a":1}"#).isEmpty)
    }

    @Test func nestedChangesReportTheirFullPath() throws {
        #expect(try diff(#"{"user":{"name":"Ada"}}"#, #"{"user":{"name":"Grace"}}"#) == [#"~ $.user.name: "Ada" → "Grace""#])
    }

    @Test func aChangedTypeIsOneChange() throws {
        #expect(try diff(#"{"a":[1]}"#, #"{"a":{"x":1}}"#) == [#"~ $.a: [1] → {"x":1}"#])
    }

    @Test func duplicateKeysUseTheLastValue() throws {
        #expect(try diff(#"{"a":1,"a":2}"#, #"{"a":2}"#).isEmpty)
    }

    // MARK: Numbers

    @Test func numbersCompareByValue() throws {
        #expect(try diff("[1.0, 100, 1e2, -0]", "[1, 1e2, 100, 0]").isEmpty)
    }

    @Test func differentNumbersAreChanges() throws {
        #expect(try diff("[1.5]", "[1.50001]") == ["~ $[0]: 1.5 → 1.50001"])
    }

    @Test func hugeNumbersFallBackToTheirText() throws {
        #expect(try diff("[1e400]", "[1e400]").isEmpty)
        #expect(try diff("[1e400]", "[2e400]") == ["~ $[0]: 1e400 → 2e400"])
    }

    // MARK: Arrays

    @Test func arraysCompareByIndexByDefault() throws {
        #expect(try diff("[1,2]", "[1,3,4]") == ["~ $[1]: 2 → 3", "+ $[2]: 4"])
        #expect(try diff("[1,2,3]", "[1]") == ["- $[1]: 2", "- $[2]: 3"])
    }

    @Test func arraysCanMatchItemsByAKey() throws {
        let old = #"[{"id":1,"v":"a"},{"id":2,"v":"b"},{"id":4,"v":"d"}]"#
        let new = #"[{"id":3,"v":"c"},{"id":1,"v":"a"},{"id":2,"v":"B"}]"#

        #expect(try diff(old, new, matchingArraysBy: "id") == [
            #"~ $[2].v: "b" → "B""#,
            #"- $[2]: {"id":4,"v":"d"}"#,
            #"+ $[0]: {"id":3,"v":"c"}"#,
        ])
    }

    @Test func matchingByKeyFallsBackToIndexWhenAnItemHasNoKey() throws {
        #expect(try diff(#"[{"id":1},2]"#, #"[2,{"id":1}]"#, matchingArraysBy: "id") == [
            #"~ $[0]: {"id":1} → 2"#,
            #"~ $[1]: 2 → {"id":1}"#,
        ])
    }

    @Test func matchingByKeyFallsBackToIndexWhenKeysRepeat() throws {
        #expect(try diff(#"[{"id":1,"v":1},{"id":1,"v":2}]"#, #"[{"id":1,"v":2},{"id":1,"v":1}]"#, matchingArraysBy: "id") == [
            "~ $[0].v: 1 → 2",
            "~ $[1].v: 2 → 1",
        ])
    }
}
