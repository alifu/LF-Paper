//
//  JSONValue.swift
//  LF-Paper
//

import Foundation

/// A parsed JSON value that keeps what the file actually says: object members stay in their
/// original order (duplicates included) and numbers keep their exact text.
nonisolated enum JSONValue: Equatable, Sendable {
    case object([JSONMember])
    case array([JSONValue])
    case string(String)
    case number(JSONNumber)
    case bool(Bool)
    case null
}

nonisolated struct JSONMember: Equatable, Sendable {
    let key: String
    let value: JSONValue
}

/// A number exactly as written, so `1.0`, `1e400` and 20-digit IDs survive a round trip.
nonisolated struct JSONNumber: Equatable, Sendable {
    let literal: String
}

/// The result of parsing: the value, plus where each value sits in the text (when requested).
nonisolated struct JSONDocument: Sendable {
    let value: JSONValue
    /// UTF-16 ranges (as used by `NSTextView`) keyed by path. With duplicate keys, the last one wins.
    let sourceRanges: [JSONPath: NSRange]
}
