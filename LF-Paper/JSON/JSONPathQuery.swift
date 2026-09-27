//
//  JSONPathQuery.swift
//  LF-Paper
//

import Foundation

/// A query that can't be read, with the 1-based column where the problem is.
nonisolated struct JSONPathQueryError: Error, Equatable, Sendable, LocalizedError {
    let message: String
    let column: Int

    var errorDescription: String? { "Column \(column): \(message)" }
}

/// One value a query found.
nonisolated struct JSONPathMatch: Equatable, Sendable {
    let path: JSONPath
    let value: JSONValue
}

/// A JSONPath query (the common subset of RFC 9535):
/// `$`, `.name`, `['name']`, `.*`, `[*]`, `..` (recursive), `[0]`, `[-1]`, `[0,2]`, `['a','b']`,
/// `[start:end:step]`, and filters such as `[?(@.price < 10 && @.isbn)]` with `== != < <= > >=`,
/// `&&`, `||`, `!` and parentheses. Filters compare numbers, strings, `true`, `false` and `null`.
nonisolated struct JSONPathQuery: Sendable {
    enum Segment: Sendable {
        /// Selects from the children of each current value.
        case child([Selector])
        /// Selects from the children of each current value and of all its descendants.
        case descendant([Selector])
    }

    enum Selector: Sendable {
        case name(String)
        case wildcard
        case index(Int)
        case slice(start: Int?, end: Int?, step: Int)
        case filter(Filter)
    }

    indirect enum Filter: Sendable {
        case exists(RelativePath)
        case comparison(Operand, Comparison, Operand)
        case not(Filter)
        case and(Filter, Filter)
        case or(Filter, Filter)
    }

    enum Operand: Sendable {
        case path(RelativePath)
        case literal(JSONValue)
    }

    enum Comparison: String, Sendable {
        case equal = "==", notEqual = "!=", less = "<", lessOrEqual = "<=", greater = ">", greaterOrEqual = ">="
    }

    /// `@` followed by names and indexes, such as `@.address.city` or `@['a'][0]`.
    struct RelativePath: Sendable {
        let components: [JSONPathComponent]
    }

    let segments: [Segment]

    static func parse(_ text: String) throws(JSONPathQueryError) -> JSONPathQuery {
        var parser = JSONPathQueryParser(text)
        return try parser.parseQuery()
    }

    /// Matches in the order the selectors produce them; a path found twice is kept once.
    func evaluate(on root: JSONValue) -> [JSONPathMatch] {
        var current = [JSONPathMatch(path: .root, value: root)]
        for segment in segments {
            current = current.flatMap { apply(segment, to: $0) }
        }
        var seen: Set<JSONPath> = []
        return current.filter { seen.insert($0.path).inserted }
    }

    // MARK: Evaluation

    private func apply(_ segment: Segment, to match: JSONPathMatch) -> [JSONPathMatch] {
        switch segment {
        case .child(let selectors):
            return selectors.flatMap { select($0, from: match) }
        case .descendant(let selectors):
            // The value itself and every descendant, in document order.
            return Self.selfAndDescendants(of: match).flatMap { node in selectors.flatMap { select($0, from: node) } }
        }
    }

    private static func selfAndDescendants(of match: JSONPathMatch) -> [JSONPathMatch] {
        [match] + children(of: match).flatMap(selfAndDescendants(of:))
    }

    private static func children(of match: JSONPathMatch) -> [JSONPathMatch] {
        switch match.value {
        case .object(let members):
            members.map { JSONPathMatch(path: match.path.appending(.key($0.key)), value: $0.value) }
        case .array(let elements):
            elements.enumerated().map { JSONPathMatch(path: match.path.appending(.index($0.offset)), value: $0.element) }
        case .string, .number, .bool, .null:
            []
        }
    }

    private func select(_ selector: Selector, from match: JSONPathMatch) -> [JSONPathMatch] {
        switch (selector, match.value) {
        case (.name(let name), .object(let members)):
            // With duplicate keys the last one wins, as in the parser's source ranges.
            return members.last { $0.key == name }.map { [JSONPathMatch(path: match.path.appending(.key(name)), value: $0.value)] } ?? []
        case (.wildcard, _):
            return Self.children(of: match)
        case (.index(let index), .array(let elements)):
            let resolved = index < 0 ? elements.count + index : index
            guard elements.indices.contains(resolved) else { return [] }
            return [JSONPathMatch(path: match.path.appending(.index(resolved)), value: elements[resolved])]
        case (.slice(let start, let end, let step), .array(let elements)):
            return Self.sliceIndexes(count: elements.count, start: start, end: end, step: step).map {
                JSONPathMatch(path: match.path.appending(.index($0)), value: elements[$0])
            }
        case (.filter(let filter), _):
            return Self.children(of: match).filter { Self.holds(filter, for: $0.value) }
        default:
            return []
        }
    }

    /// Python-style slicing, including negative bounds and steps.
    private static func sliceIndexes(count: Int, start: Int?, end: Int?, step: Int) -> [Int] {
        func normalized(_ bound: Int) -> Int { bound < 0 ? count + bound : bound }
        if step > 0 {
            let lower = min(max(normalized(start ?? 0), 0), count)
            let upper = min(max(normalized(end ?? count), 0), count)
            return Array(stride(from: lower, to: upper, by: step))
        }
        let upper = min(max(normalized(start ?? count - 1), -1), count - 1)
        let lower = min(max(normalized(end ?? -count - 1), -1), count - 1)
        return Array(stride(from: upper, to: lower, by: step))
    }

    // MARK: Filters

    private static func holds(_ filter: Filter, for value: JSONValue) -> Bool {
        switch filter {
        case .exists(let path):
            return resolve(path, in: value) != nil
        case .not(let inner):
            return !holds(inner, for: value)
        case .and(let lhs, let rhs):
            return holds(lhs, for: value) && holds(rhs, for: value)
        case .or(let lhs, let rhs):
            return holds(lhs, for: value) || holds(rhs, for: value)
        case .comparison(let lhs, let comparison, let rhs):
            return compare(operand(lhs, in: value), comparison, operand(rhs, in: value))
        }
    }

    private static func operand(_ operand: Operand, in value: JSONValue) -> JSONValue? {
        switch operand {
        case .path(let path): resolve(path, in: value)
        case .literal(let literal): literal
        }
    }

    private static func resolve(_ path: RelativePath, in value: JSONValue) -> JSONValue? {
        path.components.reduce(Optional(value)) { current, component in
            switch (component, current) {
            case (.key(let key), .object(let members)?):
                members.last { $0.key == key }?.value
            case (.index(let index), .array(let elements)?):
                elements.indices.contains(index < 0 ? elements.count + index : index)
                    ? elements[index < 0 ? elements.count + index : index] : nil
            default:
                nil
            }
        }
    }

    /// RFC 9535: `==` is true for two missing values or equal values of the same type;
    /// `!=` is its opposite; ordering compares only two numbers or two strings.
    private static func compare(_ lhs: JSONValue?, _ comparison: Comparison, _ rhs: JSONValue?) -> Bool {
        switch comparison {
        case .equal: return isEqual(lhs, rhs)
        case .notEqual: return !isEqual(lhs, rhs)
        case .less: return isLess(lhs, rhs)
        case .lessOrEqual: return isLess(lhs, rhs) || isEqual(lhs, rhs)
        case .greater: return isLess(rhs, lhs)
        case .greaterOrEqual: return isLess(rhs, lhs) || isEqual(lhs, rhs)
        }
    }

    private static func isEqual(_ lhs: JSONValue?, _ rhs: JSONValue?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case (.number(let a)?, .number(let b)?): Double(a.literal) == Double(b.literal)
        case let (a?, b?): a == b
        default: false
        }
    }

    private static func isLess(_ lhs: JSONValue?, _ rhs: JSONValue?) -> Bool {
        switch (lhs, rhs) {
        case (.number(let a)?, .number(let b)?):
            guard let x = Double(a.literal), let y = Double(b.literal) else { return false }
            return x < y
        case (.string(let a)?, .string(let b)?):
            return a < b
        default:
            return false
        }
    }
}
