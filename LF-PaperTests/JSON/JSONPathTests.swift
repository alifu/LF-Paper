//
//  JSONPathTests.swift
//  LF-PaperTests
//

import Testing
@testable import LF_Paper

struct JSONPathTests {

    @Test func rootIsADollarSign() {
        #expect(JSONPath.root.description == "$")
    }

    @Test func simpleKeysUseDotNotationAndIndexesUseBrackets() {
        let path = JSONPath.root.appending(.key("a")).appending(.index(2)).appending(.key("b_1"))

        #expect(path.description == "$.a[2].b_1")
    }

    @Test(arguments: [("with space", #"$["with space"]"#), ("1st", #"$["1st"]"#), ("", #"$[""]"#), ("a.b", #"$["a.b"]"#)])
    func otherKeysUseQuotedBrackets(key: String, expected: String) {
        #expect(JSONPath.root.appending(.key(key)).description == expected)
    }

    @Test func quotesAndBackslashesInKeysAreEscaped() {
        #expect(JSONPath.root.appending(.key(#"a"b\c"#)).description == #"$["a\"b\\c"]"#)
    }

    @Test func appendingLeavesTheOriginalUnchanged() {
        let parent = JSONPath.root.appending(.key("a"))

        _ = parent.appending(.index(0))

        #expect(parent.description == "$.a")
    }
}
