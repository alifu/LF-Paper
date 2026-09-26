//
//  JSONPath.swift
//  LF-Paper
//

import Foundation

nonisolated enum JSONPathComponent: Hashable, Sendable {
    case key(String)
    case index(Int)
}

/// The location of a value inside a document, shown as `$.users[2].name`.
nonisolated struct JSONPath: Hashable, Sendable, CustomStringConvertible {
    static let root = JSONPath(components: [])

    let components: [JSONPathComponent]

    func appending(_ component: JSONPathComponent) -> JSONPath {
        JSONPath(components: components + [component])
    }

    var description: String {
        components.reduce("$") { $0 + Self.describe($1) }
    }

    private static func describe(_ component: JSONPathComponent) -> String {
        switch component {
        case .index(let index):
            "[\(index)]"
        case .key(let key) where isIdentifier(key):
            ".\(key)"
        case .key(let key):
            "[\"\(key.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"]"
        }
    }

    /// Keys that can be written after a dot: an ASCII letter, `_` or `$`, then letters, digits, `_` or `$`.
    private static func isIdentifier(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first else { return false }
        let isHead = { (scalar: Unicode.Scalar) in
            scalar.isASCII && (scalar.properties.isAlphabetic || scalar == "_" || scalar == "$")
        }
        let isTail = { (scalar: Unicode.Scalar) in
            isHead(scalar) || ("0"..."9").contains(scalar)
        }
        return isHead(first) && key.unicodeScalars.dropFirst().allSatisfy(isTail)
    }
}
