//
//  JSONTreeNodeTests.swift
//  LF-PaperTests
//

import Testing
@testable import LF_Paper

struct JSONTreeNodeTests {
    private func root(_ json: String) throws -> JSONTreeNode {
        JSONTreeNode(root: try JSONParser.parse(json).value)
    }

    @Test func rootDescribesTheWholeDocument() throws {
        let node = try root(#"{"a":1,"b":[true,null]}"#)

        #expect(node.title == "root")
        #expect(node.path == .root)
        #expect(node.kind == .object)
        #expect(node.summary == "2 keys")
    }

    @Test func objectChildrenAreKeysInOriginalOrder() throws {
        let children = try #require(try root(#"{"b":1,"a":2}"#).children)

        #expect(children.map(\.title) == ["b", "a"])
        #expect(children.map(\.path.description) == ["$.b", "$.a"])
    }

    @Test func arrayChildrenAreIndexed() throws {
        let children = try #require(try root(#"["x",{"k":1}]"#).children)

        #expect(children.map(\.title) == ["[0]", "[1]"])
        #expect(children.map(\.path.description) == ["$[0]", "$[1]"])
        #expect(children.map(\.kind) == [.string, .object])
    }

    @Test func scalarsShowTheirValueAndHaveNoChildren() throws {
        let children = try #require(try root(#"["hi", 1.50, false, null]"#).children)

        #expect(children.map(\.summary) == [#""hi""#, "1.50", "false", "null"])
        #expect(children.map(\.kind) == [.string, .number, .bool, .null])
        #expect(children.allSatisfy { $0.children == nil && !$0.isExpandable })
    }

    @Test func countsUseSingularAndPlural() throws {
        let children = try #require(try root(#"[{}, {"a":1}, [], [1], [1,2]]"#).children)

        #expect(children.map(\.summary) == ["0 keys", "1 key", "0 items", "1 item", "2 items"])
    }

    @Test func onlyNonEmptyContainersCanExpand() throws {
        let children = try #require(try root(#"[{}, [], {"a":1}]"#).children)

        #expect(children.map(\.isExpandable) == [false, false, true])
    }

    @Test func longStringsAreShortenedAndEscaped() throws {
        let long = try root("\"" + String(repeating: "a", count: 300) + "\"")
        let multiline = try root(#""a\nb""#)

        #expect(long.summary.count < 140)
        #expect(long.summary.hasSuffix("…\""))
        #expect(multiline.summary == #""a\nb""#)
    }

    @Test func duplicateKeysAppearAsSeparateChildren() throws {
        #expect(try root(#"{"a":1,"a":2}"#).children?.map(\.summary) == ["1", "2"])
    }
}
