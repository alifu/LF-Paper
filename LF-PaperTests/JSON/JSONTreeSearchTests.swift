//
//  JSONTreeSearchTests.swift
//  LF-PaperTests
//

import Testing
@testable import LF_Paper

/// The tree pane's search field: plain text filters, text starting with `$` is a JSONPath query.
struct JSONTreeSearchTests {
    private let value: JSONValue

    init() throws {
        value = try JSONParser.parse(#"{"users": [{"name": "Ada", "tags": ["x"]}, {"name": "Grace"}], "count": 2}"#).value
    }

    private func paths(_ set: Set<JSONPath>?) -> [String]? {
        set.map { $0.map(\.description).sorted() }
    }

    @Test func blankShowsEverything() {
        let result = JSONTreeSearch.result(for: "  ", in: value)

        #expect(result.visiblePaths == nil)
        #expect(result.matchCount == nil)
        #expect(result.error == nil)
    }

    @Test func plainTextStillFiltersByKeysAndValues() {
        let result = JSONTreeSearch.result(for: "grace", in: value)

        #expect(paths(result.visiblePaths) == ["$", "$.users", "$.users[1]", "$.users[1].name"])
        #expect(result.matchCount == nil) // text filtering doesn't count matches
    }

    @Test func queriesShowMatchesTheirParentsAndWhatIsInside() {
        let result = JSONTreeSearch.result(for: "$.users[0]", in: value)

        #expect(paths(result.visiblePaths) == ["$", "$.users", "$.users[0]", "$.users[0].name", "$.users[0].tags", "$.users[0].tags[0]"])
        #expect(result.matchCount == 1)
        #expect(result.matches.map(\.description) == ["$.users[0]"])
    }

    @Test func queriesCanMatchNothing() {
        let result = JSONTreeSearch.result(for: "$.users[?(@.name == 'Linus')]", in: value)

        #expect(result.visiblePaths == [])
        #expect(result.matchCount == 0)
    }

    @Test func anInvalidQueryShowsTheErrorAndTheWholeTree() {
        let result = JSONTreeSearch.result(for: "$.users[", in: value)

        #expect(result.visiblePaths == nil)
        #expect(result.error != nil)
    }
}
