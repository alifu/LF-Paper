//
//  JSONFormatterTests.swift
//  LF-PaperTests
//

import Testing
@testable import LF_Paper

struct JSONFormatterTests {
    private let sample = #"{"name":"LF","tags":["a","b"],"empty":{},"none":[],"nested":{"n":1.0,"ok":true,"x":null}}"#

    private func value(_ text: String) throws -> JSONValue {
        try JSONParser.parse(text).value
    }

    // MARK: Pretty printing

    @Test func prettyPrintsWithTwoSpacesByDefault() throws {
        let expected = """
            {
              "name": "LF",
              "tags": [
                "a",
                "b"
              ],
              "empty": {},
              "none": [],
              "nested": {
                "n": 1.0,
                "ok": true,
                "x": null
              }
            }
            """

        #expect(JSONFormatter.pretty(try value(sample)) == expected)
    }

    @Test func prettyPrintsWithFourSpacesOrTabs() throws {
        let object = try value(#"{"a":[1]}"#)

        #expect(JSONFormatter.pretty(object, indentation: .spaces(4)) == "{\n    \"a\": [\n        1\n    ]\n}")
        #expect(JSONFormatter.pretty(object, indentation: .tab) == "{\n\t\"a\": [\n\t\t1\n\t]\n}")
    }

    @Test func scalarsPrintOnTheirOwn() throws {
        #expect(JSONFormatter.pretty(try value("  42 ")) == "42")
        #expect(JSONFormatter.pretty(try value(#""hi""#)) == #""hi""#)
    }

    // MARK: Minifying

    @Test func minifiesWithoutAnyWhitespace() throws {
        let spaced = try value("{ \"a\" : [ 1 , 2 ] , \"b\" : { } }")

        #expect(JSONFormatter.minified(spaced) == #"{"a":[1,2],"b":{}}"#)
    }

    @Test func whitespaceInsideStringsIsKept() throws {
        #expect(JSONFormatter.minified(try value(#"{"a b": " x "}"#)) == #"{"a b":" x "}"#)
    }

    // MARK: Options and fidelity

    @Test func sortsKeysAtEveryLevelWhenAsked() throws {
        let unsorted = try value(#"{"b":{"z":1,"y":2},"a":[{"d":1,"c":2}]}"#)

        #expect(JSONFormatter.minified(unsorted, sortsKeys: true) == #"{"a":[{"c":2,"d":1}],"b":{"y":2,"z":1}}"#)
        #expect(JSONFormatter.minified(unsorted) == #"{"b":{"z":1,"y":2},"a":[{"d":1,"c":2}]}"#)
    }

    @Test func numbersAreWrittenExactlyAsParsed() throws {
        let numbers = try value("[1.0, 1e400, -0, 12345678901234567890123, 2E-3]")

        #expect(JSONFormatter.minified(numbers) == "[1.0,1e400,-0,12345678901234567890123,2E-3]")
    }

    @Test func escapesStringsCorrectly() {
        let text = JSONValue.string("quote\" backslash\\ newline\n tab\t control\u{01} slash/ é 😀")

        #expect(JSONFormatter.minified(text) == #""quote\" backslash\\ newline\n tab\t control\u0001 slash/ é 😀""#)
    }

    @Test func escapesKeysToo() {
        let object = JSONValue.object([JSONMember(key: "a\"b", value: .null)])

        #expect(JSONFormatter.minified(object) == #"{"a\"b":null}"#)
    }

    // MARK: Round trips

    static let roundTripSamples = [
        #"{"name":"LF","tags":["a","b"],"empty":{},"none":[],"nested":{"n":1.0,"ok":true,"x":null}}"#,
        #"[1,-2.5e-3,"\u0000\u001f\"\\",{"😀":"日本語"},[[[]]],{"dup":1,"dup":2}]"#,
        #""just a string""#,
        "null",
    ]

    @Test(arguments: roundTripSamples)
    func formattingThenParsingGivesTheSameValue(json: String) throws {
        let original = try value(json)

        for indentation in [JSONFormatter.Indentation.spaces(2), .spaces(4), .tab] {
            #expect(try value(JSONFormatter.pretty(original, indentation: indentation)) == original)
        }
        #expect(try value(JSONFormatter.minified(original)) == original)
    }

    // MARK: Limits

    @Test func maximallyNestedDocumentsFormatAndCompareWithoutCrashing() throws {
        let depth = JSONParser.maximumDepth
        let deepest = String(repeating: #"{"a":["#, count: depth / 2) + "1" + String(repeating: "]}", count: depth / 2)
        let parsed = try value(deepest)

        let pretty = JSONFormatter.pretty(parsed)

        #expect(JSONFormatter.minified(parsed) == deepest)
        #expect(try value(pretty) == parsed)
    }

    @Test func largeDocumentsRoundTrip() throws {
        let record = #"{"id":12345678901234567890,"name":"Item \"quoted\" é","tags":["a","b"],"price":1.50,"ok":true,"none":null}"#
        let large = "[" + Array(repeating: record, count: 20_000).joined(separator: ",") + "]"

        let parsed = try value(large)

        guard case .array(let items) = parsed else {
            Issue.record("expected an array")
            return
        }
        #expect(items.count == 20_000)
        #expect(JSONFormatter.minified(parsed) == large)
    }

    @Test(arguments: roundTripSamples)
    func prettyPrintingIsStable(json: String) throws {
        let once = JSONFormatter.pretty(try value(json))

        #expect(JSONFormatter.pretty(try value(once)) == once)
    }
}
