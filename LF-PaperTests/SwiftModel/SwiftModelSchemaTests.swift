//
//  SwiftModelSchemaTests.swift
//  LF-PaperTests
//

import Testing
@testable import LF_Paper

/// From the inferred shapes to named Swift types and properties.
struct SwiftModelSchemaTests {
    private func schema(
        _ json: String,
        root: String = "User",
        keyStyle: SwiftModelOptions.KeyStyle = .camelCase
    ) throws -> SwiftModelSchema {
        try SwiftModelSchema.make(
            from: try JSONParser.parse(json).value,
            rootName: root,
            keyStyle: keyStyle,
            inference: ShapeInference.Options()
        )
    }

    private func declaration(_ name: String, in schema: SwiftModelSchema) throws -> SwiftDeclaration {
        try #require(schema.declarations.first { $0.name == name })
    }

    private func type(of name: String, in declaration: SwiftDeclaration) throws -> SwiftType {
        try #require(declaration.properties.first { $0.name == name }).type
    }

    @Test func scalarPropertiesInJSONOrder() throws {
        let schema = try schema(#"{"id": 7, "first_name": "Ada", "score": 1.5, "active": true}"#)
        let user = try declaration("User", in: schema)

        #expect(user.properties.map(\.name) == ["id", "firstName", "score", "active"])
        #expect(user.properties.map(\.jsonKey) == ["id", "first_name", "score", "active"])
        #expect(user.properties.map(\.type) == [.int, .string, .double, .bool])
        #expect(!schema.isRootArray)
        #expect(!schema.usesJSONValue)
    }

    @Test func nestedObjectsBecomeTypesDeclaredInOrder() throws {
        let schema = try schema(#"{"address": {"city": "X", "geo": {"lat": 1.5}}, "company": {"name": "Y"}}"#)

        #expect(schema.declarations.map(\.name) == ["User", "Address", "Geo", "Company"])
        #expect(try type(of: "address", in: declaration("User", in: schema)) == .named("Address"))
    }

    @Test func arraysOfObjectsAreNamedInTheSingular() throws {
        let schema = try schema(#"{"orders": [{"id": 1}], "categories": [{"id": "a"}]}"#)
        let user = try declaration("User", in: schema)

        #expect(try type(of: "orders", in: user) == .array(.named("Order")))
        #expect(try type(of: "categories", in: user) == .array(.named("Category")))
    }

    @Test func identicalShapesShareOneType() throws {
        let schema = try schema(#"{"home": {"city": "A", "zip": "1"}, "work": {"city": "B", "zip": "2"}}"#)

        #expect(schema.declarations.map(\.name) == ["User", "Home"])
        #expect(try type(of: "work", in: declaration("User", in: schema)) == .named("Home"))
    }

    @Test func differentShapesWithTheSameNameGetASuffix() throws {
        let schema = try schema(#"{"item": {"a": 1}, "list": {"item": {"b": 2}}}"#)

        #expect(schema.declarations.map(\.name) == ["User", "Item", "List", "Item2"])
    }

    @Test func aNestedTypeNamedLikeTheRootGetsASuffix() throws {
        let schema = try schema(#"{"user": {"a": 1}}"#)

        #expect(schema.declarations.map(\.name) == ["User", "User2"])
    }

    @Test func optionalsFromNullAndMissingKeys() throws {
        let schema = try schema(#"{"items": [{"a": 1, "b": 2, "c": null}, {"a": 2, "b": null}, {"a": 3}], "nothing": null}"#)
        let item = try declaration("Item", in: schema)

        #expect(try type(of: "a", in: item) == .int)
        #expect(try type(of: "b", in: item) == .optional(.int)) // null in one item, missing in another
        #expect(try type(of: "c", in: item) == .optional(.jsonValue)) // only ever null: the type is unknown
        #expect(try type(of: "nothing", in: declaration("User", in: schema)) == .optional(.jsonValue))
        #expect(schema.usesJSONValue)
    }

    @Test func emptyArraysAndMixedValuesUseJSONValue() throws {
        let schema = try schema(#"{"tags": [], "values": [1, "a"]}"#)
        let user = try declaration("User", in: schema)
        let tags = try #require(user.properties.first { $0.name == "tags" })

        #expect(tags.type == .array(.jsonValue))
        #expect(tags.isUnknownItemType)
        #expect(try type(of: "values", in: user) == .array(.jsonValue))
        #expect(schema.usesJSONValue)
    }

    @Test func datesAndURLsAreNoted() throws {
        let schema = try schema(#"{"at": "2026-09-27T10:15:00Z", "site": "https://a.com"}"#)

        #expect(try type(of: "at", in: declaration("User", in: schema)) == .date)
        #expect(try type(of: "site", in: declaration("User", in: schema)) == .url)
        #expect(schema.usesDates)
    }

    @Test func clashingPropertyNamesGetASuffix() throws {
        let schema = try schema(#"{"first_name": "a", "firstName": "b"}"#)

        #expect(try declaration("User", in: schema).properties.map(\.name) == ["firstName", "firstName2"])
    }

    @Test func namesThatBreakGeneratedCodeGetASuffix() throws {
        let schema = try schema(#"{"self": 1, "CodingKeys": 2, "Self": 3, "selfValue": 4}"#, keyStyle: .keep)

        #expect(try declaration("User", in: schema).properties.map(\.name) == ["selfValue", "CodingKeysValue", "SelfValue", "selfValue2"])
    }

    @Test func keptKeyNames() throws {
        let schema = try schema(#"{"first_name": "a", "user-id": 1}"#, keyStyle: .keep)

        #expect(try declaration("User", in: schema).properties.map(\.name) == ["first_name", "userId"])
    }

    @Test func aTopLevelArrayOfObjectsNamesItsItems() throws {
        let schema = try schema(#"[{"id": 1}, {"id": 2, "name": "b"}]"#)

        #expect(schema.isRootArray)
        #expect(schema.declarations.map(\.name) == ["User"])
        #expect(try declaration("User", in: schema).properties.map(\.name) == ["id", "name"])
    }

    @Test(arguments: ["1", #""text""#, "[1, 2]", "[]", "null", "[[{}]]"])
    func otherTopLevelsCantBeModelled(json: String) {
        #expect(throws: SwiftModelError.topLevelNotObject) {
            try schema(json)
        }
    }

    @Test func anInvalidRootNameIsCleanedUp() throws {
        #expect(try schema("{}", root: "my model").declarations.map(\.name) == ["MyModel"])
        #expect(try schema("{}", root: "").declarations.map(\.name) == ["Root"])
    }

    @Test func nestedArraysOfArrays() throws {
        let schema = try schema(#"{"grid": [[{"v": 1}]]}"#)

        #expect(try type(of: "grid", in: declaration("User", in: schema)) == .array(.array(.named("GridItem"))))
    }

    @Test func optionalArrayItems() throws {
        let schema = try schema(#"{"names": ["a", null]}"#)

        #expect(try type(of: "names", in: declaration("User", in: schema)) == .array(.optional(.string)))
    }
}
