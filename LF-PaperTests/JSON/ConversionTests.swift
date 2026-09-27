//
//  ConversionTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

/// YAML ↔ JSON and CSV ↔ JSON, including round trips, quoting and empty documents.
struct ConversionTests {
    private func json(_ text: String) throws -> JSONValue {
        try JSONParser.parse(text).value
    }

    private func minified(_ value: JSONValue) -> String {
        JSONFormatter.minified(value)
    }

    // MARK: YAML → JSON

    @Test func yamlBecomesJSONInTheSameOrder() throws {
        let yaml = """
            name: Ada
            age: 36
            ratio: 1.5
            active: true
            nickname: null
            tags:
              - math
              - "42"
            address:
              city: London
            """

        #expect(try minified(YAMLConversion.json(fromYAML: yaml)) ==
            #"{"name":"Ada","age":36,"ratio":1.5,"active":true,"nickname":null,"tags":["math","42"],"address":{"city":"London"}}"#)
    }

    @Test func yamlAliasesAreExpandedAndKeysBecomeStrings() throws {
        let yaml = """
            base: &base {x: 1}
            copy: *base
            1: one
            """

        #expect(try minified(YAMLConversion.json(fromYAML: yaml)) == #"{"base":{"x":1},"copy":{"x":1},"1":"one"}"#)
    }

    @Test func emptyYAMLIsNull() throws {
        #expect(try YAMLConversion.json(fromYAML: "") == .null)
        #expect(try YAMLConversion.json(fromYAML: "# just a comment\n") == .null)
    }

    @Test func yamlThatJSONCannotHoldIsReported() {
        #expect(throws: ConversionError.self) { _ = try YAMLConversion.json(fromYAML: "value: .inf") }
        #expect(throws: ConversionError.self) { _ = try YAMLConversion.json(fromYAML: "a: 1\n---\nb: 2") }
        #expect(throws: ConversionError.self) { _ = try YAMLConversion.json(fromYAML: "a: [unclosed") }
    }

    // MARK: JSON → YAML

    @Test func jsonBecomesYAMLThatReadsBackTheSame() throws {
        let original = try json(#"{"name":"Ada","count":12345678901234567890,"pi":3.14,"on":true,"none":null,"list":[1,"two",{"k":"v"}],"empty":{},"none2":[]}"#)

        let yaml = try YAMLConversion.yaml(from: original)
        #expect(try YAMLConversion.json(fromYAML: yaml) == original)
        #expect(yaml.hasPrefix("name: Ada\n"))
    }

    @Test func stringsThatLookLikeOtherTypesStayStrings() throws {
        let original = try json(#"{"a":"123","b":"true","c":"null","d":"","e":"line one\nline two","f":"key: value","g":"- dash"}"#)

        #expect(try YAMLConversion.json(fromYAML: YAMLConversion.yaml(from: original)) == original)
    }

    // MARK: CSV parsing

    @Test func csvFieldsHandleQuotesCommasAndNewlines() throws {
        let csv = "name,notes\r\nAda,\"says \"\"hi\"\", then leaves\"\n\"Grace\",\"line one\nline two\"\n"

        #expect(try CSVConversion.rows(fromCSV: csv) == [
            ["name", "notes"],
            ["Ada", #"says "hi", then leaves"#],
            ["Grace", "line one\nline two"],
        ])
    }

    @Test func anUnclosedQuoteIsReported() {
        #expect(throws: ConversionError.self) { _ = try CSVConversion.rows(fromCSV: "a\n\"unclosed") }
    }

    // MARK: CSV → JSON

    @Test func csvRowsBecomeObjectsWithNumbersAndBooleansRecognised() throws {
        let csv = "id,name,score,active,zip\n1,Ada,9.5,true,01234\n2,Grace,,false,90210\n"

        #expect(try minified(CSVConversion.json(fromCSV: csv)) ==
            #"[{"id":1,"name":"Ada","score":9.5,"active":true,"zip":"01234"},{"id":2,"name":"Grace","score":"","active":false,"zip":90210}]"#)
    }

    @Test func shortRowsAreFilledAndLongRowsAreReported() throws {
        #expect(try minified(CSVConversion.json(fromCSV: "a,b\n1\n")) == #"[{"a":1,"b":""}]"#)
        #expect(throws: ConversionError.self) { _ = try CSVConversion.json(fromCSV: "a,b\n1,2,3\n") }
    }

    @Test func emptyCSVIsAnEmptyArray() throws {
        #expect(try CSVConversion.json(fromCSV: "") == .array([]))
        #expect(try CSVConversion.json(fromCSV: "a,b\n") == .array([]))
    }

    // MARK: JSON → CSV

    @Test func flatObjectsBecomeRowsUnderOneHeader() throws {
        let value = try json(#"[{"name":"Ada","note":"says \"hi\", then leaves","age":36},{"name":"Grace","active":true,"note":null}]"#)

        #expect(try CSVConversion.csv(from: value) == """
            name,note,age,active\r
            Ada,"says ""hi"", then leaves",36,\r
            Grace,,,true\r

            """)
    }

    @Test func csvRoundTripKeepsTheRows() throws {
        let value = try json(#"[{"a":"x, y","b":"multi\nline","c":2},{"a":" padded ","b":"","c":3}]"#)

        #expect(try CSVConversion.json(fromCSV: CSVConversion.csv(from: value)) == value)
    }

    @Test func onlyArraysOfFlatObjectsBecomeCSV() throws {
        #expect(throws: ConversionError.self) { _ = try CSVConversion.csv(from: json(#"{"a":1}"#)) }
        #expect(throws: ConversionError.self) { _ = try CSVConversion.csv(from: json("[1, 2]")) }
        #expect(throws: ConversionError.self) { _ = try CSVConversion.csv(from: json(#"[{"a":{"nested":1}}]"#)) }
        #expect(try CSVConversion.csv(from: json("[]")) == "")
    }

    @Test func errorsSayWhatIsWrong() throws {
        let error = try #require(throws: ConversionError.self) { _ = try CSVConversion.csv(from: json(#"[{"a":1},{"a":[2]}]"#)) }

        #expect(error.localizedDescription == "Item [1] has a list or object in “a”; CSV can only hold plain values.")
    }
}
