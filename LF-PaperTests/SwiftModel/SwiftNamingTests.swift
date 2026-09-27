//
//  SwiftNamingTests.swift
//  LF-PaperTests
//

import Testing
@testable import LF_Paper

/// Turning JSON keys into Swift property and type names.
struct SwiftNamingTests {
    @Test(arguments: [
        ("first_name", "firstName"),
        ("firstName", "firstName"),
        ("FirstName", "firstName"),
        ("URL", "url"),
        ("userID", "userID"),
        ("user-id", "userId"),
        ("Content-Type", "contentType"),
        ("__v", "v"),
        ("2fa_code", "_2faCode"),
        ("first name", "firstName"),
        ("café_au_lait", "caféAuLait"),
        ("", "value"),
        ("---", "value"),
    ])
    func camelCasePropertyNames(key: String, name: String) {
        #expect(SwiftNaming.propertyName(for: key, style: .camelCase) == name)
    }

    @Test func keptNamesStayUnlessTheyArentValidSwift() {
        #expect(SwiftNaming.propertyName(for: "first_name", style: .keep) == "first_name")
        #expect(SwiftNaming.propertyName(for: "default", style: .keep) == "default")
        #expect(SwiftNaming.propertyName(for: "user-id", style: .keep) == "userId")
        #expect(SwiftNaming.propertyName(for: "2x", style: .keep) == "_2x")
    }

    @Test(arguments: ["default", "class", "self", "Type", "func", "in", "is", "protocol", "where"])
    func keywordsAreEscaped(name: String) {
        #expect(SwiftNaming.escaped(name) == "`\(name)`")
    }

    @Test func ordinaryNamesArentEscaped() {
        #expect(SwiftNaming.escaped("name") == "name")
        #expect(SwiftNaming.escaped("firstName") == "firstName")
    }

    @Test(arguments: [
        ("user", "User"),
        ("first_name", "FirstName"),
        ("shippingAddress", "ShippingAddress"),
        ("2fa", "_2fa"),
        ("data", "DataObject"),
        ("date", "DateObject"),
        ("type", "TypeObject"),
        ("JSONValue", "JSONValueObject"),
        ("", "Value"),
    ])
    func typeNames(key: String, name: String) {
        #expect(SwiftNaming.typeName(for: key) == name)
    }

    @Test(arguments: [
        ("Users", "User"),
        ("Categories", "Category"),
        ("Addresses", "Address"),
        ("Boxes", "Box"),
        ("Matches", "Match"),
        ("Status", "Status"),
        ("OrderItems", "OrderItem"),
        ("People", "Person"),
        ("Children", "Child"),
        ("Data", "Data"),
    ])
    func singulars(plural: String, singular: String) {
        #expect(SwiftNaming.singular(plural) == singular)
    }

    @Test func arrayItemsAreNamedInTheSingular() {
        #expect(SwiftNaming.elementTypeName(for: "users") == "User")
        #expect(SwiftNaming.elementTypeName(for: "order_items") == "OrderItem")
        #expect(SwiftNaming.elementTypeName(for: "status") == "StatusItem")
        #expect(SwiftNaming.elementTypeName(for: "data") == "DataItem")
    }

    @Test func rootNamesComeFromTheFileName() {
        #expect(SwiftNaming.rootTypeName(forFileNamed: "users.json") == "User")
        #expect(SwiftNaming.rootTypeName(forFileNamed: "order-history.json") == "OrderHistory")
        #expect(SwiftNaming.rootTypeName(forFileNamed: "config.json") == "Config")
        #expect(SwiftNaming.rootTypeName(forFileNamed: ".json") == "Root")
    }

    @Test func validIdentifiers() {
        #expect(SwiftNaming.isValidIdentifier("name"))
        #expect(SwiftNaming.isValidIdentifier("_private2"))
        #expect(!SwiftNaming.isValidIdentifier("2x"))
        #expect(!SwiftNaming.isValidIdentifier("first-name"))
        #expect(!SwiftNaming.isValidIdentifier(""))
        #expect(!SwiftNaming.isValidIdentifier("_"))
    }
}
