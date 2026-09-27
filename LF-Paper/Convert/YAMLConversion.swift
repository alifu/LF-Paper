//
//  YAMLConversion.swift
//  LF-Paper
//

import Foundation
import Yams

/// Why a conversion couldn't be done, in words for an alert.
nonisolated struct ConversionError: Error, Equatable, Sendable, LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

/// YAML ↔ JSON with Yams. Keys keep their order both ways, numbers keep their exact text, and
/// strings that would read as another type (`"123"`, `"true"`, `""`) are quoted in YAML.
nonisolated enum YAMLConversion {
    /// The first (and only) YAML document as JSON. Empty YAML is `null`.
    static func json(fromYAML yaml: String) throws(ConversionError) -> JSONValue {
        let root: Node?
        do {
            root = try Yams.compose(yaml: yaml)
        } catch {
            throw ConversionError(message: "This isn’t valid YAML: \(describe(error))")
        }
        guard let root else { return .null }
        return try json(from: root)
    }

    static func yaml(from value: JSONValue) throws(ConversionError) -> String {
        do {
            return try Yams.serialize(node: node(from: value), sortKeys: false)
        } catch {
            throw ConversionError(message: "The YAML couldn’t be written: \(describe(error))")
        }
    }

    // MARK: YAML → JSON

    private static func json(from node: Node) throws(ConversionError) -> JSONValue {
        switch node {
        case .scalar(let scalar):
            return try json(from: scalar)
        case .sequence(let sequence):
            var elements: [JSONValue] = []
            for element in sequence {
                elements.append(try json(from: element))
            }
            return .array(elements)
        case .mapping(let mapping):
            var members: [JSONMember] = []
            for (key, value) in mapping {
                // Keys that aren't text (such as `1:` or a list) become their text or JSON form.
                let name = if let scalar = key.scalar { scalar.string } else { JSONFormatter.minified(try json(from: key)) }
                members.append(JSONMember(key: name, value: try json(from: value)))
            }
            return .object(members)
        case .alias:
            throw ConversionError(message: "This YAML has an alias that couldn’t be followed.")
        }
    }

    private static func json(from scalar: Node.Scalar) throws(ConversionError) -> JSONValue {
        switch Resolver.default.resolveTag(of: .scalar(scalar)) {
        case .null:
            return .null
        case .bool:
            return Bool.construct(from: scalar).map(JSONValue.bool) ?? .string(scalar.string)
        case .int:
            if JSONNumberLiteral.isValid(scalar.string) { return .number(JSONNumber(literal: scalar.string)) }
            guard let integer = Int.construct(from: scalar) else { return .string(scalar.string) }
            return .number(JSONNumber(literal: String(integer)))
        case .float:
            if JSONNumberLiteral.isValid(scalar.string) { return .number(JSONNumber(literal: scalar.string)) }
            guard let number = Double.construct(from: scalar) else { return .string(scalar.string) }
            guard number.isFinite else {
                throw ConversionError(message: "“\(scalar.string)” has no JSON equivalent (JSON has no infinity or NaN).")
            }
            return .number(JSONNumber(literal: String(number)))
        default:
            // Strings, and types JSON doesn't have (such as timestamps), as their text.
            return .string(scalar.string)
        }
    }

    // MARK: JSON → YAML

    private static func node(from value: JSONValue) -> Node {
        switch value {
        case .object(let members):
            return Node(members.map { (stringNode($0.key), node(from: $0.value)) })
        case .array(let elements):
            return Node(elements.map(node(from:)))
        case .string(let text):
            return stringNode(text)
        case .number(let number):
            return Node(number.literal, Tag(.float))
        case .bool(let flag):
            return Node(flag ? "true" : "false", Tag(.bool))
        case .null:
            return Node("null", Tag(.null))
        }
    }

    /// A string, quoted when written plainly it would read back as something else.
    private static func stringNode(_ text: String) -> Node {
        let readsAsString = Resolver.default.resolveTag(of: Node(text)) == .str
        return Node(text, Tag(.str), readsAsString ? .any : .doubleQuoted)
    }

    private static func describe(_ error: any Error) -> String {
        (error as? YamlError).map { String(describing: $0) } ?? error.localizedDescription
    }
}

/// JSON's number syntax, for keeping a YAML number's text exactly when it's already valid JSON.
nonisolated enum JSONNumberLiteral {
    static func isValid(_ text: String) -> Bool {
        text.wholeMatch(of: /-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/) != nil
    }
}
