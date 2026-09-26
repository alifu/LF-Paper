//
//  JSONParserTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

struct JSONParserTests {
    private func parse(_ text: String) throws -> JSONValue {
        try JSONParser.parse(text).value
    }

    private func number(_ literal: String) -> JSONValue {
        .number(JSONNumber(literal: literal))
    }

    private func parseError(_ text: String) -> JSONParseError? {
        do throws(JSONParseError) {
            _ = try JSONParser.parse(text)
            return nil
        } catch {
            return error
        }
    }

    // MARK: Values

    @Test func parsesLiterals() throws {
        #expect(try parse("true") == .bool(true))
        #expect(try parse("false") == .bool(false))
        #expect(try parse("null") == .null)
    }

    @Test(arguments: ["0", "-0", "42", "-7", "3.14", "-0.5e10", "1E+2", "2e-3"])
    func parsesNumbersKeepingTheirLiteral(literal: String) throws {
        #expect(try parse(literal) == number(literal))
    }

    @Test func numbersBeyondDoublePrecisionAreKeptExactly() throws {
        #expect(try parse("12345678901234567890123") == number("12345678901234567890123"))
        #expect(try parse("1e400") == number("1e400"))
        #expect(try parse("1.0") == number("1.0"))
    }

    @Test func objectsKeepKeyOrder() throws {
        let value = try parse(#"{"b": 1, "a": 2, "c": 3}"#)

        #expect(value == .object([
            JSONMember(key: "b", value: number("1")),
            JSONMember(key: "a", value: number("2")),
            JSONMember(key: "c", value: number("3")),
        ]))
    }

    @Test func duplicateKeysAreAllKept() throws {
        let value = try parse(#"{"a": 1, "a": 2}"#)

        #expect(value == .object([JSONMember(key: "a", value: number("1")), JSONMember(key: "a", value: number("2"))]))
    }

    @Test func parsesNestedContainersAndWhitespace() throws {
        let value = try parse(" {\n\t\"list\" : [ 1 , [ ] , { } , \"x\" ] \r\n} ")

        #expect(value == .object([
            JSONMember(key: "list", value: .array([number("1"), .array([]), .object([]), .string("x")])),
        ]))
    }

    @Test func ignoresALeadingByteOrderMark() throws {
        #expect(try parse("\u{FEFF}[1]") == .array([number("1")]))
    }

    // MARK: Strings

    @Test func decodesEscapes() throws {
        #expect(try parse(#""a\"b\\c\/d\n\t\r\b\fé""#) == .string("a\"b\\c/d\n\t\r\u{08}\u{0C}é"))
    }

    @Test func decodesSurrogatePairs() throws {
        #expect(try parse(#""😀""#) == .string("😀"))
    }

    @Test func keepsRawUnicode() throws {
        #expect(try parse(#""日本語 😀""#) == .string("日本語 😀"))
    }

    // MARK: Errors

    @Test func emptyInputExpectsAValue() {
        let error = parseError("")

        #expect(error?.reason == .unexpectedEnd(expected: "a value"))
        #expect(error?.line == 1 && error?.column == 1)
    }

    @Test func trailingCommaInObjectIsRejectedAtTheBrace() {
        let error = parseError(#"{"a":1,}"#)

        #expect(error?.reason == .unexpectedCharacter(found: "}", expected: "a string key"))
        #expect(error?.line == 1 && error?.column == 8)
    }

    @Test func trailingCommaInArrayIsRejected() {
        #expect(parseError("[1,]")?.reason == .unexpectedCharacter(found: "]", expected: "a value"))
    }

    @Test func missingColonIsReported() {
        #expect(parseError(#"{"a" 1}"#)?.reason == .unexpectedCharacter(found: "1", expected: "':' after the key"))
    }

    @Test func unclosedArrayReportsTheEnd() {
        let error = parseError("[1,2")

        #expect(error?.reason == .unexpectedEnd(expected: "',' or ']'"))
        #expect(error?.column == 5)
    }

    @Test func lineAndColumnCountFromOne() {
        let error = parseError("{\n  \"a\": 1,\n  @")

        #expect(error?.line == 3)
        #expect(error?.column == 3)
    }

    @Test func unterminatedStringPointsAtItsStart() {
        let error = parseError(#"["abc"#)

        #expect(error?.reason == .unterminatedString)
        #expect(error?.column == 2)
    }

    @Test func invalidEscapeIsRejected() {
        #expect(parseError(#""a\qb""#)?.reason == .invalidEscape)
        #expect(parseError(#""\u12G4""#)?.reason == .invalidEscape)
    }

    @Test func rawControlCharactersInStringsAreRejected() {
        #expect(parseError("\"tab\there\"")?.reason == .unescapedControlCharacter)
    }

    @Test(arguments: ["1.", "-", "1e", "1e+", "-.5"])
    func malformedNumbersAreRejected(text: String) {
        #expect(parseError(text)?.reason == .invalidNumber)
    }

    @Test func leadingZerosLeaveTrailingContent() {
        #expect(parseError("01")?.reason == .trailingContent)
    }

    @Test func misspelledLiteralsAreRejected() {
        #expect(parseError("tru")?.reason == .unexpectedCharacter(found: "t", expected: "true"))
        #expect(parseError("nul")?.reason == .unexpectedCharacter(found: "n", expected: "null"))
    }

    @Test func contentAfterTheValueIsRejected() {
        #expect(parseError("1 2")?.reason == .trailingContent)
        #expect(parseError("{} x")?.reason == .trailingContent)
    }

    @Test func commentsAreNotJSON() {
        #expect(parseError("// note\n1")?.reason == .unexpectedCharacter(found: "/", expected: "a value"))
    }

    @Test func nestingIsLimited() throws {
        let limit = JSONParser.maximumDepth
        let deepestAllowed = String(repeating: "[", count: limit) + String(repeating: "]", count: limit)
        let tooDeep = String(repeating: "[", count: limit + 1) + String(repeating: "]", count: limit + 1)

        #expect(throws: Never.self) { try JSONParser.parse(deepestAllowed) }
        #expect(parseError(tooDeep)?.reason == .nestingTooDeep(limit: limit))
    }

    @Test func errorDescriptionIncludesThePosition() {
        let description = parseError(#"{"a":1,}"#)?.errorDescription

        #expect(description == "Line 1, column 8: Expected a string key but found “}”.")
    }

    @Test(arguments: [
        ("[1, 2", "Expected"),
        ("1.", "This number isn’t valid JSON."),
        (#""\q""#, "Invalid escape sequence in a string."),
        ("\"a\tb\"", "control characters must be escaped"),
        (#""open"#, "This string is never closed."),
        ("1 2", "Unexpected text after the JSON value."),
        (String(repeating: "[", count: JSONParser.maximumDepth + 1), "Nesting is deeper than"),
    ])
    func everyErrorExplainsItself(text: String, explanation: String) throws {
        let description = try #require(parseError(text)?.errorDescription)

        #expect(description.hasPrefix("Line 1, column "))
        #expect(description.contains(explanation), "\(description)")
    }

    // MARK: Source ranges

    @Test func recordsTheSourceRangeOfEveryValue() throws {
        let text = #"{"a": [10, "x"]}"# as NSString

        let ranges = try JSONParser.parse(text as String, recordsSourceRanges: true).sourceRanges

        func source(_ path: JSONPath) -> String? { ranges[path].map(text.substring(with:)) }
        #expect(source(.root) == text as String)
        #expect(source(JSONPath.root.appending(.key("a"))) == #"[10, "x"]"#)
        #expect(source(JSONPath.root.appending(.key("a")).appending(.index(0))) == "10")
        #expect(source(JSONPath.root.appending(.key("a")).appending(.index(1))) == #""x""#)
        #expect(ranges.count == 4)
    }

    @Test func sourceRangesUseUTF16Offsets() throws {
        let ranges = try JSONParser.parse(#"{"😀": 1}"#, recordsSourceRanges: true).sourceRanges

        #expect(ranges[JSONPath.root.appending(.key("😀"))] == NSRange(location: 7, length: 1))
    }

    @Test func sourceRangesAreOnlyRecordedWhenAsked() throws {
        #expect(try JSONParser.parse("[1, 2]").sourceRanges.isEmpty)
    }
}
