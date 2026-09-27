//
//  JSONSchemaSupport.swift
//  LF-Paper
//

import Foundation

/// JSON Schema's type names and how problems describe values.
nonisolated enum JSONSchemaTypes {
    static func value(_ value: JSONValue, isOfType type: String) -> Bool {
        switch (type, value) {
        case ("object", .object), ("array", .array), ("string", .string), ("number", .number), ("boolean", .bool), ("null", .null):
            true
        case ("integer", .number(let number)):
            // 3.0 counts as an integer in JSON Schema.
            Double(number.literal).map { $0.isFinite && $0 == $0.rounded() } ?? false
        default:
            false
        }
    }

    /// "a string", "an integer", "null": how a type reads in a problem.
    static func describe(_ type: String) -> String {
        switch type {
        case "object", "array", "integer": "an \(type)"
        case "null": "null"
        default: "a \(type)"
        }
    }

    static func describe(_ value: JSONValue) -> String {
        switch value {
        case .object: "an object"
        case .array: "an array"
        case .string: "a string"
        case .number: "a number"
        case .bool: "a boolean"
        case .null: "null"
        }
    }
}

/// Equality as JSON Schema means it: numbers by value, object keys in any order.
nonisolated enum JSONEquality {
    static func isEqual(_ lhs: JSONValue, _ rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.number(let a), .number(let b)):
            return a.literal == b.literal || (Double(a.literal).map { $0 == Double(b.literal) } ?? false)
        case (.array(let a), .array(let b)):
            return a.count == b.count && zip(a, b).allSatisfy(isEqual)
        case (.object(let a), .object(let b)):
            let left = Dictionary(a.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
            let right = Dictionary(b.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
            return left.count == right.count && left.allSatisfy { key, value in right[key].map { isEqual(value, $0) } ?? false }
        default:
            return lhs == rhs
        }
    }
}

/// JSON Pointer (RFC 6901), as used after the `#` of a `$ref`: `/$defs/name`, with `~1` for `/`
/// and `~0` for `~`. The empty pointer is the whole document.
nonisolated enum JSONPointer {
    static func resolve(_ pointer: String, in root: JSONValue) -> JSONValue? {
        let decoded = pointer.removingPercentEncoding ?? pointer
        guard !decoded.isEmpty else { return root }
        guard decoded.hasPrefix("/") else { return nil }
        return decoded.dropFirst().split(separator: "/", omittingEmptySubsequences: false).reduce(Optional(root)) { current, token in
            let key = token.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
            switch current {
            case .object(let members)?:
                return members.last { $0.key == key }?.value
            case .array(let elements)?:
                guard let index = Int(key), elements.indices.contains(index) else { return nil }
                return elements[index]
            default:
                return nil
            }
        }
    }
}
