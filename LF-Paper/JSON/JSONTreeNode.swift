//
//  JSONTreeNode.swift
//  LF-Paper
//

import Foundation

/// A value in the JSON tree view: its label, path, type and a one-line summary.
/// Children are built on demand, so huge documents only pay for what's expanded.
nonisolated struct JSONTreeNode: Identifiable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        case object, array, string, number, bool, null
    }

    /// Strings longer than this are shortened in the summary.
    private static let summaryLimit = 120

    /// The key, `[index]`, or "root".
    let title: String
    let path: JSONPath
    let value: JSONValue

    var id: JSONPath { path }

    init(root value: JSONValue) {
        self.init(title: "root", path: .root, value: value)
    }

    private init(title: String, path: JSONPath, value: JSONValue) {
        self.title = title
        self.path = path
        self.value = value
    }

    var kind: Kind {
        switch value {
        case .object: .object
        case .array: .array
        case .string: .string
        case .number: .number
        case .bool: .bool
        case .null: .null
        }
    }

    /// `nil` for scalars; possibly empty for `{}` and `[]`.
    var children: [JSONTreeNode]? {
        switch value {
        case .object(let members):
            members.map { JSONTreeNode(title: $0.key, path: path.appending(.key($0.key)), value: $0.value) }
        case .array(let elements):
            elements.enumerated().map { index, element in
                JSONTreeNode(title: "[\(index)]", path: path.appending(.index(index)), value: element)
            }
        case .string, .number, .bool, .null:
            nil
        }
    }

    var isExpandable: Bool {
        switch value {
        case .object(let members): !members.isEmpty
        case .array(let elements): !elements.isEmpty
        case .string, .number, .bool, .null: false
        }
    }

    /// "3 keys", "1 item", or the scalar as JSON (long strings shortened).
    var summary: String {
        switch value {
        case .object(let members):
            Self.count(members.count, singular: "key", plural: "keys")
        case .array(let elements):
            Self.count(elements.count, singular: "item", plural: "items")
        case .string(let text) where text.count > Self.summaryLimit:
            JSONFormatter.quoted(String(text.prefix(Self.summaryLimit)) + "…")
        case .string(let text):
            JSONFormatter.quoted(text)
        case .number(let number):
            number.literal
        case .bool(let flag):
            flag ? "true" : "false"
        case .null:
            "null"
        }
    }

    private static func count(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}
