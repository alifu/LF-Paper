//
//  JSONPathQueryTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

/// JSONPath queries over parsed documents: each selector, filters, and invalid queries.
struct JSONPathQueryTests {
    private static let store = #"""
        {
          "store": {
            "book": [
              {"category": "reference", "author": "Nigel Rees", "title": "Sayings", "price": 8.95},
              {"category": "fiction", "author": "Evelyn Waugh", "title": "Sword", "price": 12.99, "isbn": "0-553"},
              {"category": "fiction", "author": "Herman Melville", "title": "Moby Dick", "price": 8.99, "isbn": "0-395"},
              {"category": "fiction", "author": "J. R. R. Tolkien", "title": "The Lord", "price": 22.99, "active": true}
            ],
            "bicycle": {"color": "red", "price": 19.95}
          },
          "odd key": 1
        }
        """#

    private func paths(_ query: String, in text: String = Self.store) throws -> [String] {
        let value = try JSONParser.parse(text).value
        return try JSONPathQuery.parse(query).evaluate(on: value).map(\.path.description)
    }

    private func values(_ query: String) throws -> [String] {
        let value = try JSONParser.parse(Self.store).value
        return try JSONPathQuery.parse(query).evaluate(on: value).map { JSONFormatter.minified($0.value) }
    }

    @Test func rootAndChildNames() throws {
        #expect(try paths("$") == ["$"])
        #expect(try paths("$.store.bicycle.color") == ["$.store.bicycle.color"])
        #expect(try paths(#"$['store']["bicycle"]"#) == ["$.store.bicycle"])
        #expect(try paths("$['odd key']") == [#"$["odd key"]"#])
    }

    @Test func missingNamesMatchNothing() throws {
        #expect(try paths("$.store.car").isEmpty)
        #expect(try paths("$.store.book.title").isEmpty) // book is an array, not an object
    }

    @Test func wildcards() throws {
        #expect(try paths("$.store.bicycle.*") == ["$.store.bicycle.color", "$.store.bicycle.price"])
        #expect(try paths("$.store.book[*].author").count == 4)
    }

    @Test func indexesIncludingFromTheEnd() throws {
        #expect(try values("$.store.book[0].title") == [#""Sayings""#])
        #expect(try values("$.store.book[-1].title") == [#""The Lord""#])
        #expect(try paths("$.store.book[9]").isEmpty)
    }

    @Test func unionsOfIndexesAndNames() throws {
        #expect(try values("$.store.book[0,2].title") == [#""Sayings""#, #""Moby Dick""#])
        #expect(try paths("$.store.bicycle['color','price']") == ["$.store.bicycle.color", "$.store.bicycle.price"])
    }

    @Test func slices() throws {
        #expect(try values("$.store.book[1:3].title") == [#""Sword""#, #""Moby Dick""#])
        #expect(try values("$.store.book[:2].title") == [#""Sayings""#, #""Sword""#])
        #expect(try values("$.store.book[-2:].title") == [#""Moby Dick""#, #""The Lord""#])
        #expect(try values("$.store.book[::2].title") == [#""Sayings""#, #""Moby Dick""#])
        #expect(try values("$.store.book[::-1].title").first == #""The Lord""#)
    }

    @Test func recursiveDescent() throws {
        #expect(try paths("$..price") == [
            "$.store.book[0].price", "$.store.book[1].price", "$.store.book[2].price", "$.store.book[3].price",
            "$.store.bicycle.price",
        ])
        #expect(try paths("$..book[0].author") == ["$.store.book[0].author"])
        #expect(try paths("$.store..color") == ["$.store.bicycle.color"])
    }

    @Test func filtersOnExistence() throws {
        #expect(try values("$.store.book[?(@.isbn)].title") == [#""Sword""#, #""Moby Dick""#])
        #expect(try values("$.store.book[?@.active].title") == [#""The Lord""#]) // parentheses are optional
        #expect(try values("$.store.book[?(!@.isbn)].title") == [#""Sayings""#, #""The Lord""#])
    }

    @Test func filtersWithComparisons() throws {
        #expect(try values("$.store.book[?(@.price < 10)].title") == [#""Sayings""#, #""Moby Dick""#])
        #expect(try values("$.store.book[?(@.price >= 22.99)].title") == [#""The Lord""#])
        #expect(try values("$.store.book[?(@.category == 'reference')].author") == [#""Nigel Rees""#])
        #expect(try values(#"$.store.book[?(@.category != "fiction")].title"#) == [#""Sayings""#])
        #expect(try values("$.store.book[?(@.active == true)].title") == [#""The Lord""#])
    }

    @Test func filtersCombineWithAndOrAndParentheses() throws {
        #expect(try values("$.store.book[?(@.category == 'fiction' && @.price < 10)].title") == [#""Moby Dick""#])
        #expect(try values("$.store.book[?(@.price > 20 || @.category == 'reference')].title") == [#""Sayings""#, #""The Lord""#])
        #expect(try values("$.store.book[?(!(@.price > 9) && @.isbn)].title") == [#""Moby Dick""#])
    }

    @Test func comparisonsAcrossTypesAreFalse() throws {
        #expect(try paths("$.store.book[?(@.price == '8.95')]").isEmpty)
        #expect(try paths("$.store.book[?(@.missing < 3)]").isEmpty)
    }

    @Test func filtersOnObjectMembers() throws {
        #expect(try paths("$.store[?(@.color)]") == ["$.store.bicycle"])
    }

    @Test(arguments: [
        "", "store", "$.", "$[", "$[1", "$['a", "$[?(@.a ==)]", "$[?(@.a", "$..", "$[1:2:0]", "$.a b", "$[?(@.a === 1)]",
    ])
    func invalidQueriesAreReported(query: String) {
        #expect(throws: JSONPathQueryError.self) {
            _ = try JSONPathQuery.parse(query)
        }
    }

    @Test func errorsSayWhere() throws {
        let error = try #require(throws: JSONPathQueryError.self) { _ = try JSONPathQuery.parse("$.store[?(@.price >)]") }
        #expect(error.column == 20) // the ")" where a value should be
        #expect(error.localizedDescription.hasPrefix("Column 20:"))
    }

    @Test func resultsAreInDocumentOrderWithoutDuplicates() throws {
        #expect(try paths("$.store.book[0,0]") == ["$.store.book[0]"])
        #expect(try paths("$..[?(@.color)]") == ["$.store.bicycle"])
    }
}
