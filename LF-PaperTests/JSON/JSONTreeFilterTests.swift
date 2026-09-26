//
//  JSONTreeFilterTests.swift
//  LF-PaperTests
//

import Testing
@testable import LF_Paper

struct JSONTreeFilterTests {
    private let value: JSONValue

    init() throws {
        value = try JSONParser.parse(#"{"user":{"name":"Ada","age":36},"tags":["math","code"],"active":true}"#).value
    }

    private func visible(_ query: String) -> Set<String>? {
        JSONTreeFilter.visiblePaths(in: value, matching: query).map { Set($0.map(\.description)) }
    }

    @Test func blankQueryMeansNoFilter() {
        #expect(visible("") == nil)
        #expect(visible("   ") == nil)
    }

    @Test func matchingAKeyShowsItWithItsAncestors() throws {
        let paths = try #require(visible("name"))

        #expect(paths == ["$", "$.user", "$.user.name"])
    }

    @Test func matchingAContainerKeyShowsEverythingInside() throws {
        let paths = try #require(visible("user"))

        #expect(paths == ["$", "$.user", "$.user.name", "$.user.age"])
    }

    @Test func matchingAValueShowsIt() throws {
        let paths = try #require(visible("math"))

        #expect(paths == ["$", "$.tags", "$.tags[0]"])
    }

    @Test func matchingIgnoresCase() throws {
        #expect(try #require(visible("ADA")).contains("$.user.name"))
    }

    @Test func numbersAndLiteralsMatchTheirText() throws {
        #expect(try #require(visible("36")).contains("$.user.age"))
        #expect(try #require(visible("true")).contains("$.active"))
    }

    @Test func noMatchesGivesAnEmptySet() {
        #expect(visible("zzz") == [])
    }
}
