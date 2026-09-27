//
//  SwiftModelSchema.swift
//  LF-Paper
//

import Foundation

nonisolated enum SwiftModelError: Error, Equatable, Sendable, LocalizedError {
    case topLevelNotObject

    var errorDescription: String? {
        switch self {
        case .topLevelNotObject:
            "A model needs an object, or a list of objects, at the top level of the JSON."
        }
    }
}

/// A property's Swift type.
nonisolated indirect enum SwiftType: Hashable, Sendable {
    case bool
    case int
    case double
    case string
    case date
    case url
    /// A generated type.
    case named(String)
    case array(SwiftType)
    case optional(SwiftType)
    /// Values whose type differs or is unknown: the generated `JSONValue` (or `Any`).
    case jsonValue
}

nonisolated struct SwiftProperty: Hashable, Sendable {
    let jsonKey: String
    /// Unescaped; use `SwiftNaming.escaped` in code.
    let name: String
    let type: SwiftType
    /// Every array seen here was empty, so the item type is a guess.
    let isUnknownItemType: Bool

    var isOptional: Bool {
        if case .optional = type { true } else { false }
    }
}

nonisolated struct SwiftDeclaration: Hashable, Sendable {
    let name: String
    let properties: [SwiftProperty]

    /// Whether any property's name differs from its JSON key, so `CodingKeys` are needed.
    var needsCodingKeys: Bool { properties.contains { $0.name != $0.jsonKey } }
}

/// The types to generate for a JSON sample: the root first, then each nested type in the order it
/// first appears. Objects with the same shape share one type; different ones with the same name get a number.
nonisolated struct SwiftModelSchema: Equatable, Sendable {
    let declarations: [SwiftDeclaration]
    /// The JSON is a list of root objects.
    let isRootArray: Bool
    let usesJSONValue: Bool
    let usesDates: Bool

    var rootName: String { declarations[0].name }

    static func make(
        from value: JSONValue,
        rootName: String,
        keyStyle: SwiftModelOptions.KeyStyle,
        inference: ShapeInference.Options
    ) throws(SwiftModelError) -> SwiftModelSchema {
        try make(from: ShapeInference.shape(of: value, options: inference), rootName: rootName, keyStyle: keyStyle)
    }

    /// From an already inferred shape.
    static func make(from shaped: Shaped, rootName: String, keyStyle: SwiftModelOptions.KeyStyle) throws(SwiftModelError) -> SwiftModelSchema {
        let fields: [FieldShape]
        let isRootArray: Bool
        switch shaped.shape {
        case .object(let rootFields):
            (fields, isRootArray) = (rootFields, false)
        case .array(let items?):
            guard case .object(let itemFields)? = items.shape else { throw .topLevelNotObject }
            (fields, isRootArray) = (itemFields, true)
        default:
            throw .topLevelNotObject
        }
        var builder = Builder(keyStyle: keyStyle)
        let hasName = rootName.contains { $0.isLetter || $0.isNumber }
        builder.declare(fields, suggestedName: hasName ? SwiftNaming.typeName(for: rootName) : "Root")
        return SwiftModelSchema(
            declarations: builder.declarations.compactMap { $0 },
            isRootArray: isRootArray,
            usesJSONValue: builder.usesJSONValue,
            usesDates: builder.usesDates
        )
    }

    /// Names and declares types depth first, so each type follows the one that first uses it.
    private struct Builder {
        /// Property names that break generated code even with backticks: `self` in an initializer,
        /// and `CodingKeys`, which would hide the nested enum. They get "Value" added.
        private static let reservedPropertyNames: Set<String> = ["self", "Self", "CodingKeys"]

        let keyStyle: SwiftModelOptions.KeyStyle
        /// `nil` while a type's properties are still being worked out.
        var declarations: [SwiftDeclaration?] = []
        var namesByShape: [[FieldShape]: String] = [:]
        var usedNames: Set<String> = []
        var usesJSONValue = false
        var usesDates = false

        /// Returns the type's name, declaring it if this shape hasn't been seen.
        @discardableResult
        mutating func declare(_ fields: [FieldShape], suggestedName: String) -> String {
            if let existing = namesByShape[fields] { return existing }
            let name = unique(suggestedName, in: usedNames)
            usedNames.insert(name)
            namesByShape[fields] = name
            let index = declarations.count
            declarations.append(nil)
            var propertyNames: Set<String> = []
            var properties: [SwiftProperty] = []
            for field in fields {
                let suggested = SwiftNaming.propertyName(for: field.key, style: keyStyle)
                let safe = Self.reservedPropertyNames.contains(suggested) ? suggested + "Value" : suggested
                let propertyName = unique(safe, in: propertyNames)
                propertyNames.insert(propertyName)
                let type = swiftType(for: field.value, key: field.key, isArrayItem: false)
                properties.append(SwiftProperty(
                    jsonKey: field.key,
                    name: propertyName,
                    type: type,
                    isUnknownItemType: Self.hasEmptyArray(field.value)
                ))
            }
            declarations[index] = SwiftDeclaration(name: name, properties: properties)
            return name
        }

        private mutating func swiftType(for value: Shaped, key: String, isArrayItem: Bool) -> SwiftType {
            let type: SwiftType
            switch value.shape {
            case nil:
                usesJSONValue = true
                type = .jsonValue
            case .bool?: type = .bool
            case .int?: type = .int
            case .double?: type = .double
            case .string?: type = .string
            case .date?:
                usesDates = true
                type = .date
            case .url?: type = .url
            case .mixed?:
                usesJSONValue = true
                type = .jsonValue
            case .object(let fields)?:
                let suggested = isArrayItem ? SwiftNaming.elementTypeName(for: key) : SwiftNaming.typeName(for: key)
                type = .named(declare(fields, suggestedName: suggested))
            case .array(let items)?:
                if let items {
                    type = .array(swiftType(for: items, key: key, isArrayItem: true))
                } else {
                    usesJSONValue = true
                    type = .array(.jsonValue)
                }
            }
            return value.isOptional ? .optional(type) : type
        }

        private static func hasEmptyArray(_ value: Shaped) -> Bool {
            switch value.shape {
            case .array(nil)?: true
            case .array(let items?)?: hasEmptyArray(items)
            default: false
            }
        }

        private func unique(_ name: String, in used: Set<String>) -> String {
            guard used.contains(name) else { return name }
            return (2...).lazy.map { "\(name)\($0)" }.first { !used.contains($0) }!
        }
    }
}
