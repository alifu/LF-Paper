//
//  JSONPathQueryParser.swift
//  LF-Paper
//

import Foundation

/// Reads the text of a JSONPath query into a `JSONPathQuery`, reporting the column of any problem.
nonisolated struct JSONPathQueryParser {
    private let characters: [Character]
    private var position = 0

    init(_ text: String) {
        characters = Array(text)
    }

    mutating func parseQuery() throws(JSONPathQueryError) -> JSONPathQuery {
        skipSpaces()
        guard take("$") else { throw error("A query starts with $") }
        var segments: [JSONPathQuery.Segment] = []
        while true {
            skipSpaces()
            guard !isAtEnd else { break }
            segments.append(try parseSegment())
        }
        return JSONPathQuery(segments: segments)
    }

    // MARK: Segments

    private mutating func parseSegment() throws(JSONPathQueryError) -> JSONPathQuery.Segment {
        if take("..") {
            if peek == "[" {
                return .descendant(try parseBracket())
            }
            return .descendant([try parseDotSelector()])
        }
        if take(".") {
            return .child([try parseDotSelector()])
        }
        if peek == "[" {
            return .child(try parseBracket())
        }
        throw error("Expected “.” or “[”")
    }

    /// After a dot: a name or `*`.
    private mutating func parseDotSelector() throws(JSONPathQueryError) -> JSONPathQuery.Selector {
        if take("*") { return .wildcard }
        let name = takeWhile { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" || $0 == "-" }
        guard !name.isEmpty else { throw error("Expected a name or * after the dot") }
        return .name(name)
    }

    /// `[…]` with one or more comma-separated selectors.
    private mutating func parseBracket() throws(JSONPathQueryError) -> [JSONPathQuery.Selector] {
        try expect("[")
        var selectors: [JSONPathQuery.Selector] = []
        repeat {
            skipSpaces()
            selectors.append(try parseBracketSelector())
            skipSpaces()
        } while take(",")
        try expect("]")
        return selectors
    }

    private mutating func parseBracketSelector() throws(JSONPathQueryError) -> JSONPathQuery.Selector {
        if take("*") { return .wildcard }
        if peek == "'" || peek == "\"" { return .name(try parseString()) }
        if take("?") { return .filter(try parseFilterExpression()) }
        return try parseIndexOrSlice()
    }

    private mutating func parseIndexOrSlice() throws(JSONPathQueryError) -> JSONPathQuery.Selector {
        let start = try parseOptionalInteger()
        skipSpaces()
        guard take(":") else {
            guard let start else { throw error("Expected an index, a name in quotes, *, a slice or a filter") }
            return .index(start)
        }
        skipSpaces()
        let end = try parseOptionalInteger()
        skipSpaces()
        var step = 1
        if take(":") {
            skipSpaces()
            step = try parseOptionalInteger() ?? 1
            guard step != 0 else { throw error("A slice step can't be 0") }
        }
        return .slice(start: start, end: end, step: step)
    }

    // MARK: Filters

    /// `?(expression)` or `?expression`, with `||` binding looser than `&&`, and `!` tightest.
    private mutating func parseFilterExpression() throws(JSONPathQueryError) -> JSONPathQuery.Filter {
        skipSpaces()
        return try parseOr()
    }

    private mutating func parseOr() throws(JSONPathQueryError) -> JSONPathQuery.Filter {
        var filter = try parseAnd()
        while true {
            skipSpaces()
            guard take("||") else { return filter }
            filter = .or(filter, try parseAnd())
        }
    }

    private mutating func parseAnd() throws(JSONPathQueryError) -> JSONPathQuery.Filter {
        var filter = try parseUnary()
        while true {
            skipSpaces()
            guard take("&&") else { return filter }
            filter = .and(filter, try parseUnary())
        }
    }

    private mutating func parseUnary() throws(JSONPathQueryError) -> JSONPathQuery.Filter {
        skipSpaces()
        if peek == "!" && peek(1) != "=" {
            position += 1
            return .not(try parseUnary())
        }
        if take("(") {
            let inner = try parseOr()
            skipSpaces()
            try expect(")")
            return inner
        }
        return try parseComparison()
    }

    private mutating func parseComparison() throws(JSONPathQueryError) -> JSONPathQuery.Filter {
        let lhs = try parseOperand()
        skipSpaces()
        guard let comparison = takeComparison() else {
            guard case .path(let path) = lhs else { throw error("Expected a comparison after the value") }
            return .exists(path)
        }
        skipSpaces()
        let rhs = try parseOperand()
        return .comparison(lhs, comparison, rhs)
    }

    private mutating func takeComparison() -> JSONPathQuery.Comparison? {
        for comparison in [JSONPathQuery.Comparison.equal, .notEqual, .lessOrEqual, .greaterOrEqual, .less, .greater] {
            if take(comparison.rawValue) {
                return comparison
            }
        }
        return nil
    }

    private mutating func parseOperand() throws(JSONPathQueryError) -> JSONPathQuery.Operand {
        skipSpaces()
        if take("@") { return .path(try parseRelativePath()) }
        if peek == "'" || peek == "\"" { return .literal(.string(try parseString())) }
        for (word, value) in [("true", JSONValue.bool(true)), ("false", .bool(false)), ("null", .null)] where take(word) {
            return .literal(value)
        }
        let number = takeWhile { $0.isNumber || $0 == "-" || $0 == "+" || $0 == "." || $0 == "e" || $0 == "E" }
        guard !number.isEmpty, Double(number) != nil else { throw error("Expected @, a number, a string, true, false or null") }
        return .literal(.number(JSONNumber(literal: number)))
    }

    private mutating func parseRelativePath() throws(JSONPathQueryError) -> JSONPathQuery.RelativePath {
        var components: [JSONPathComponent] = []
        while true {
            if take(".") {
                let name = takeWhile { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" || $0 == "-" }
                guard !name.isEmpty else { throw error("Expected a name after the dot") }
                components.append(.key(name))
            } else if peek == "[" {
                position += 1
                skipSpaces()
                if peek == "'" || peek == "\"" {
                    components.append(.key(try parseString()))
                } else if let index = try parseOptionalInteger() {
                    components.append(.index(index))
                } else {
                    throw error("Expected a name in quotes or an index")
                }
                skipSpaces()
                try expect("]")
            } else {
                return JSONPathQuery.RelativePath(components: components)
            }
        }
    }

    // MARK: Tokens

    private mutating func parseString() throws(JSONPathQueryError) -> String {
        guard let quote = peek, quote == "'" || quote == "\"" else { throw error("Expected a quote") }
        position += 1
        var text = ""
        while let character = peek {
            position += 1
            if character == quote { return text }
            if character == "\\", let escaped = peek {
                position += 1
                text.append(escaped)
            } else {
                text.append(character)
            }
        }
        throw error("This string is never closed")
    }

    private mutating func parseOptionalInteger() throws(JSONPathQueryError) -> Int? {
        let start = position
        _ = take("-")
        let digits = takeWhile(\.isNumber)
        guard !digits.isEmpty else {
            position = start
            return nil
        }
        guard let value = Int(String(characters[start..<position])) else { throw error("This number is too large") }
        return value
    }

    private var isAtEnd: Bool { position >= characters.count }
    private var peek: Character? { peek(0) }

    private func peek(_ offset: Int) -> Character? {
        characters.indices.contains(position + offset) ? characters[position + offset] : nil
    }

    private mutating func take(_ text: String) -> Bool {
        let expected = Array(text)
        guard position + expected.count <= characters.count, Array(characters[position..<(position + expected.count)]) == expected else {
            return false
        }
        position += expected.count
        return true
    }

    private mutating func expect(_ text: String) throws(JSONPathQueryError) {
        guard take(text) else { throw error(isAtEnd ? "Expected “\(text)” but the query ended" : "Expected “\(text)”") }
    }

    private mutating func takeWhile(_ predicate: (Character) -> Bool) -> String {
        let start = position
        while let character = peek, predicate(character) {
            position += 1
        }
        return String(characters[start..<position])
    }

    private mutating func skipSpaces() {
        while let character = peek, character == " " {
            position += 1
        }
    }

    private func error(_ message: String) -> JSONPathQueryError {
        JSONPathQueryError(message: message, column: position + 1)
    }
}
