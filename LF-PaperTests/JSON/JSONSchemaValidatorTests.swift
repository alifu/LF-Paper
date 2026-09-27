//
//  JSONSchemaValidatorTests.swift
//  LF-PaperTests
//

import Testing
@testable import LF_Paper

/// JSON Schema keywords: a passing and a failing document for each, with paths and messages.
struct JSONSchemaValidatorTests {
    private func problems(_ document: String, _ schema: String) throws -> [String] {
        let value = try JSONParser.parse(document).value
        let schemaValue = try JSONParser.parse(schema).value
        return JSONSchemaValidator.validate(value, against: schemaValue).map { "\($0.path): \($0.message)" }
    }

    @Test func types() throws {
        #expect(try problems(#""x""#, #"{"type": "string"}"#).isEmpty)
        #expect(try problems("3", #"{"type": ["string", "null"]}"#) == ["$: Expected a string or null, found a number"])
        #expect(try problems("3.0", #"{"type": "integer"}"#).isEmpty) // 3.0 is an integer in JSON Schema
        #expect(try problems("3.5", #"{"type": "integer"}"#) == ["$: Expected an integer, found a number"])
        #expect(try problems("[]", #"{"type": "object"}"#) == ["$: Expected an object, found an array"])
    }

    @Test func requiredPropertiesAndAdditionalProperties() throws {
        let schema = #"""
            {"type": "object", "required": ["name", "age"],
             "properties": {"name": {"type": "string"}, "age": {"type": "integer"}},
             "additionalProperties": false}
            """#

        #expect(try problems(#"{"name": "Ada", "age": 36}"#, schema).isEmpty)
        #expect(try problems(#"{"name": 1, "nickname": "A"}"#, schema) == [
            "$: “age” is required",
            "$.name: Expected a string, found a number",
            "$.nickname: “nickname” isn’t allowed here",
        ])
    }

    @Test func additionalPropertiesCanBeASchema() throws {
        #expect(try problems(#"{"a": 1, "b": "x"}"#, #"{"additionalProperties": {"type": "number"}}"#) == [
            "$.b: Expected a number, found a string",
        ])
    }

    @Test func itemsCountsAndUniqueness() throws {
        let schema = #"{"type": "array", "items": {"type": "number"}, "minItems": 2, "maxItems": 3, "uniqueItems": true}"#

        #expect(try problems("[1, 2]", schema).isEmpty)
        #expect(try problems(#"[1, "x", 1, 4]"#, schema) == [
            "$: Must have at most 3 items",
            "$: Items must be unique ([0] and [2] are the same)",
            "$[1]: Expected a number, found a string",
        ])
        #expect(try problems("[1]", schema) == ["$: Must have at least 2 items"])
    }

    @Test func tupleItems() throws {
        #expect(try problems(#"[1, "x"]"#, #"{"prefixItems": [{"type": "number"}, {"type": "number"}]}"#) == [
            "$[1]: Expected a number, found a string",
        ])
        #expect(try problems(#"[1, "x"]"#, #"{"items": [{"type": "number"}, {"type": "string"}]}"#).isEmpty)
    }

    @Test func enumAndConst() throws {
        #expect(try problems(#""red""#, #"{"enum": ["red", "green"]}"#).isEmpty)
        #expect(try problems(#""blue""#, #"{"enum": ["red", "green"]}"#) == [#"$: Must be one of: "red", "green""#])
        #expect(try problems("2", #"{"const": 1}"#) == ["$: Must be 1"])
        #expect(try problems("1.0", #"{"const": 1}"#).isEmpty) // numbers compare by value
    }

    @Test func numberLimits() throws {
        let schema = #"{"minimum": 0, "maximum": 10, "exclusiveMaximum": 10, "multipleOf": 0.5}"#

        #expect(try problems("9.5", schema).isEmpty)
        #expect(try problems("-1", schema) == ["$: Must be at least 0"])
        #expect(try problems("10", schema) == ["$: Must be less than 10"])
        #expect(try problems("0.3", schema) == ["$: Must be a multiple of 0.5"])
    }

    @Test func stringLengthAndPattern() throws {
        let schema = #"{"minLength": 2, "maxLength": 4, "pattern": "^[a-z]+$"}"#

        #expect(try problems(#""abc""#, schema).isEmpty)
        #expect(try problems(#""a""#, schema) == ["$: Must be at least 2 characters"])
        #expect(try problems(#""abcde""#, schema) == ["$: Must be at most 4 characters"])
        #expect(try problems(#""AB""#, schema) == ["$: Must match the pattern ^[a-z]+$"])
        #expect(try problems(#""😀😀""#, #"{"maxLength": 2}"#).isEmpty) // characters, not UTF-16 units
    }

    @Test func propertyCounts() throws {
        #expect(try problems("{}", #"{"minProperties": 1}"#) == ["$: Must have at least 1 property"])
        #expect(try problems(#"{"a":1,"b":2}"#, #"{"maxProperties": 1}"#) == ["$: Must have at most 1 property"])
    }

    @Test func combinations() throws {
        #expect(try problems("5", #"{"allOf": [{"type": "number"}, {"minimum": 10}]}"#) == ["$: Must be at least 10"])
        #expect(try problems("true", #"{"anyOf": [{"type": "string"}, {"type": "number"}]}"#) == [
            "$: Doesn’t match any of the allowed shapes (anyOf)",
        ])
        #expect(try problems("5", #"{"oneOf": [{"type": "number"}, {"minimum": 1}]}"#) == [
            "$: Must match exactly one of the allowed shapes, but matches 2 (oneOf)",
        ])
        #expect(try problems(#""x""#, #"{"not": {"type": "string"}}"#) == ["$: Must not match the schema in “not”"])
    }

    @Test func booleanSchemas() throws {
        #expect(try problems("1", "true").isEmpty)
        #expect(try problems("1", "false") == ["$: No value is allowed here"])
        #expect(try problems(#"{"a": 1}"#, #"{"properties": {"a": false}}"#) == ["$.a: No value is allowed here"])
    }

    @Test func localReferences() throws {
        let schema = #"""
            {"$defs": {"positive": {"type": "number", "minimum": 1}},
             "definitions": {"name": {"type": "string"}},
             "properties": {"count": {"$ref": "#/$defs/positive"}, "name": {"$ref": "#/definitions/name"}}}
            """#

        #expect(try problems(#"{"count": 0, "name": 3}"#, schema) == [
            "$.count: Must be at least 1",
            "$.name: Expected a string, found a number",
        ])
    }

    @Test func recursiveReferencesAreFollowedButCyclesStop() throws {
        let tree = ##"{"type": "object", "properties": {"child": {"$ref": "#"}, "name": {"type": "string"}}}"##
        #expect(try problems(#"{"child": {"child": {"name": 1}}}"#, tree) == ["$.child.child.name: Expected a string, found a number"])

        let loop = ##"{"$defs": {"a": {"$ref": "#/$defs/b"}, "b": {"$ref": "#/$defs/a"}}, "$ref": "#/$defs/a"}"##
        #expect(try problems("1", loop) == ["$: The schema’s $ref goes round in a circle"])
    }

    @Test func unknownReferencesAreReported() throws {
        #expect(try problems("1", ##"{"$ref": "#/$defs/missing"}"##) == ["$: The schema’s $ref “#/$defs/missing” doesn’t point to anything"])
        #expect(try problems("1", #"{"$ref": "other.json#/x"}"#) == ["$: Only $ref inside the same schema (starting with #) is supported"])
    }

    @Test func unknownKeywordsAreIgnored() throws {
        #expect(try problems(#""x""#, #"{"format": "email", "title": "Name", "description": "…"}"#).isEmpty)
    }
}

/// The helpers behind `$ref` and `enum`/`const`: JSON Pointer and JSON Schema equality.
struct JSONSchemaSupportTests {
    private let document: JSONValue

    init() throws {
        document = try JSONParser.parse(#"{"a/b": {"c~d": [10, 20]}, "e f": true}"#).value
    }

    @Test func pointersUnescapeSlashesAndTildesAndIndexArrays() {
        #expect(JSONPointer.resolve("/a~1b/c~0d/1", in: document) == .number(JSONNumber(literal: "20")))
        #expect(JSONPointer.resolve("/e%20f", in: document) == .bool(true)) // percent-encoded, as in a URL fragment
        #expect(JSONPointer.resolve("", in: document) == document)
        #expect(JSONPointer.resolve("/missing", in: document) == nil)
        #expect(JSONPointer.resolve("/a~1b/c~0d/9", in: document) == nil)
        #expect(JSONPointer.resolve("no-slash", in: document) == nil)
    }

    @Test func equalityIgnoresKeyOrderAndNumberSpelling() throws {
        let a = try JSONParser.parse(#"{"x": 1, "y": [1.0, "s"]}"#).value
        let b = try JSONParser.parse(#"{"y": [1, "s"], "x": 1e0}"#).value
        let c = try JSONParser.parse(#"{"y": [1, "s"], "x": 2}"#).value

        #expect(JSONEquality.isEqual(a, b))
        #expect(!JSONEquality.isEqual(a, c))
        #expect(!JSONEquality.isEqual(.string("1"), .number(JSONNumber(literal: "1"))))
    }

    @Test func typeNamesReadNaturally() {
        #expect(JSONSchemaTypes.describe("object") == "an object")
        #expect(JSONSchemaTypes.describe("boolean") == "a boolean")
        #expect(JSONSchemaTypes.describe("null") == "null")
        #expect(JSONSchemaTypes.describe(.bool(true)) == "a boolean")
        #expect(JSONSchemaTypes.describe(.null) == "null")
        #expect(JSONSchemaTypes.value(.bool(true), isOfType: "boolean"))
        #expect(!JSONSchemaTypes.value(.string("x"), isOfType: "made-up"))
    }
}
