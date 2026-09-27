//
//  DictionaryModelWriter.swift
//  LF-Paper
//

import Foundation

/// Structs that read and write the `[String: Any]` dictionaries of `JSONSerialization`:
/// `init?(dictionary:)` fails when a required value is missing or has another type.
/// Values whose type differs or is unknown are `Any`.
nonisolated struct DictionaryModelWriter {
    let schema: SwiftModelSchema
    let options: SwiftModelOptions

    private var access: String { SwiftModelGenerator.accessPrefix(options) }

    func declarations() -> [String] {
        schema.declarations.map(declaration) + helpers()
    }

    /// The computed property that turns a value back into a dictionary: `dictionary`, or the first
    /// of `jsonDictionary`, `jsonDictionary2`… that no JSON key took.
    private func dictionaryPropertyName(of typeName: String) -> String {
        let taken = Set(schema.declarations.first { $0.name == typeName }?.properties.map(\.name) ?? [])
        guard taken.contains("dictionary") else { return "dictionary" }
        var name = "jsonDictionary"
        var number = 1
        while taken.contains(name) {
            number += 1
            name = "jsonDictionary\(number)"
        }
        return name
    }

    private func declaration(_ declaration: SwiftDeclaration) -> String {
        let binding = options.usesVar ? "var" : "let"
        let properties = declaration.properties.map { property in
            let comment = property.isUnknownItemType ? " // empty in the sample, so the item type is unknown" : ""
            return "    \(access)\(binding) \(SwiftNaming.escaped(property.name)): \(spelling(of: property.type))\(comment)"
        }.joined(separator: "\n")
        let sections = [properties, initializer(for: declaration), dictionaryProperty(for: declaration)].filter { !$0.isEmpty }
        let conformances = isIdentifiable(declaration) ? ": Identifiable" : ""
        return "\(access)struct \(declaration.name)\(conformances) {\n\(sections.joined(separator: "\n\n"))\n}"
    }

    /// `Identifiable` needs a `Hashable` id, which `Any` isn't.
    private func isIdentifiable(_ declaration: SwiftDeclaration) -> Bool {
        guard options.effectiveConformances.contains(.identifiable),
              let id = declaration.properties.first(where: { $0.name == "id" })
        else { return false }
        return isHashable(id.type)
    }

    /// Only plain values are `Hashable` here: `Any` isn't, and dictionary-based types don't conform.
    private func isHashable(_ type: SwiftType) -> Bool {
        switch type {
        case .bool, .int, .double, .string, .date, .url: true
        case .jsonValue, .named: false
        case .array(let item), .optional(let item): isHashable(item)
        }
    }

    private func initializer(for declaration: SwiftDeclaration) -> String {
        let assignments = declaration.properties.map { property in
            let name = SwiftNaming.escaped(property.name)
            let source = "dictionary[\(SwiftModelGenerator.stringLiteral(property.jsonKey))]"
            if case .optional(let wrapped) = property.type {
                return "        self.\(name) = \(decoding(wrapped, from: source))"
            }
            // Parentheses, because a trailing closure can't stand in an `if let` condition.
            let decoded = decoding(property.type, from: source)
            let condition = decoded.contains("{") ? "(\(decoded))" : decoded
            return "        if let value = \(condition) { self.\(name) = value } else { return nil }"
        }
        return (["    \(access)init?(dictionary: [String: Any]) {"] + assignments + ["    }"]).joined(separator: "\n")
    }

    private func dictionaryProperty(for declaration: SwiftDeclaration) -> String {
        let assignments = declaration.properties.map { property in
            let key = SwiftModelGenerator.stringLiteral(property.jsonKey)
            let value = "self.\(SwiftNaming.escaped(property.name))"
            if case .optional(let wrapped) = property.type {
                let encoded = encoding(wrapped, "$0")
                return "        json[\(key)] = \(encoded == "$0" ? value : "\(value).map { \(encoded) }")"
            }
            return "        json[\(key)] = \(encoding(property.type, value))"
        }
        return (
            ["    \(access)var \(dictionaryPropertyName(of: declaration.name)): [String: Any] {", "        var json: [String: Any] = [:]"]
                + assignments
                + ["        return json", "    }"]
        ).joined(separator: "\n")
    }

    /// An expression that turns `source` (an `Any?`) into the type, or `nil` when it doesn't fit.
    private func decoding(_ type: SwiftType, from source: String) -> String {
        switch type {
        case .bool: "\(source) as? Bool"
        case .int: "\(source) as? Int"
        case .double: "\(source) as? Double"
        case .string: "\(source) as? String"
        case .jsonValue: source
        case .date: "(\(source) as? String).flatMap { ISO8601DateFormatter().date(from: $0) }"
        case .url: "(\(source) as? String).flatMap { URL(string: $0) }"
        case .named(let name): "(\(source) as? [String: Any]).flatMap { \(name)(dictionary: $0) }"
        case .array(.optional(let item)): "decodeOptionalItems(\(source)) { \(decoding(item, from: "$0")) }"
        case .array(let item): "decodeItems(\(source)) { \(decoding(item, from: "$0")) }"
        case .optional(let wrapped): decoding(wrapped, from: source)
        }
    }

    /// An expression that turns `value` back into what `JSONSerialization` writes.
    private func encoding(_ type: SwiftType, _ value: String) -> String {
        switch type {
        case .bool, .int, .double, .string, .jsonValue: value
        case .date: "ISO8601DateFormatter().string(from: \(value))"
        case .url: "\(value).absoluteString"
        case .named(let name): "\(value).\(dictionaryPropertyName(of: name))"
        case .array(.optional(let item)): "\(value).map { $0.map { \(encoding(item, "$0")) as Any } ?? NSNull() }"
        case .array(let item):
            encoding(item, "$0") == "$0" ? value : "\(value).map { \(encoding(item, "$0")) }"
        case .optional(let wrapped): "\(value).map { \(encoding(wrapped, "$0")) as Any } ?? NSNull()"
        }
    }

    private func spelling(of type: SwiftType) -> String {
        switch type {
        case .bool: "Bool"
        case .int: "Int"
        case .double: "Double"
        case .string: "String"
        case .date: "Date"
        case .url: "URL"
        case .named(let name): name
        case .array(let item): "[\(spelling(of: item))]"
        case .optional(let wrapped): "\(spelling(of: wrapped))?"
        case .jsonValue: "Any"
        }
    }

    private func helpers() -> [String] {
        let types = schema.declarations.flatMap { $0.properties.map(\.type) }
        var helpers: [String] = []
        if types.contains(where: { usesArrayHelper(in: $0, optionalItems: false) }) {
            helpers.append("""
            /// The items of a JSON array, or `nil` when it isn't one or an item doesn't fit.
            private func decodeItems<T>(_ value: Any?, _ decode: (Any) -> T?) -> [T]? {
                guard let items = value as? [Any] else { return nil }
                let decoded = items.compactMap(decode)
                return decoded.count == items.count ? decoded : nil
            }
            """)
        }
        if types.contains(where: { usesArrayHelper(in: $0, optionalItems: true) }) {
            helpers.append("""
            /// The items of a JSON array that can hold `null`, which (like items that don't fit) become `nil`.
            private func decodeOptionalItems<T>(_ value: Any?, _ decode: (Any) -> T?) -> [T?]? {
                (value as? [Any])?.map(decode)
            }
            """)
        }
        return helpers
    }

    private func usesArrayHelper(in type: SwiftType, optionalItems: Bool) -> Bool {
        switch type {
        case .array(.optional(let item)): optionalItems || usesArrayHelper(in: item, optionalItems: optionalItems)
        case .array(let item): !optionalItems || usesArrayHelper(in: item, optionalItems: optionalItems)
        case .optional(let wrapped): usesArrayHelper(in: wrapped, optionalItems: optionalItems)
        default: false
        }
    }
}
