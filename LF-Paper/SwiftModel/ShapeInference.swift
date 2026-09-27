//
//  ShapeInference.swift
//  LF-Paper
//

import Foundation

/// What one position in the JSON holds across the whole sample: its shape (`nil` when only
/// `null` was seen) and whether it's `null` or missing somewhere.
nonisolated struct Shaped: Hashable, Sendable {
    let shape: ValueShape?
    let isOptional: Bool
}

nonisolated indirect enum ValueShape: Hashable, Sendable {
    case bool
    case int
    case double
    case string
    /// An ISO 8601 date and time, as `JSONDecoder`'s `.iso8601` strategy reads it.
    case date
    /// An `http:` or `https:` address.
    case url
    /// Members in the order they first appear.
    case object([FieldShape])
    /// `nil` when every array was empty, so the item type is unknown.
    case array(Shaped?)
    /// Values of kinds that don't merge (text in one place, an object in another).
    case mixed
}

nonisolated struct FieldShape: Hashable, Sendable {
    let key: String
    let value: Shaped
}

/// Infers the shape of a JSON sample: array items are merged into one shape, keys missing
/// from some objects become optional, and `Int` with `Double` becomes `Double`.
nonisolated enum ShapeInference {
    struct Options: Equatable, Sendable {
        var detectsDates = true
        var detectsURLs = true
    }

    // Documented as thread safe; this is the formatter `JSONDecoder.DateDecodingStrategy.iso8601` uses.
    private nonisolated(unsafe) static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func shape(of value: JSONValue, options: Options) -> Shaped {
        switch value {
        case .null:
            Shaped(shape: nil, isOptional: true)
        case .bool:
            required(.bool)
        case .number(let number):
            required(isInteger(number.literal) ? .int : .double)
        case .string(let text):
            required(stringShape(text, options: options))
        case .array(let items):
            required(.array(items.map { shape(of: $0, options: options) }.reduce(nil, mergeItems)))
        case .object(let members):
            required(.object(fields(of: members, options: options)))
        }
    }

    /// The shape that fits both: the union of object keys, `Double` for mixed numbers, text for
    /// text mixed with dates or addresses, and `.mixed` for anything else that differs.
    static func merge(_ lhs: Shaped, _ rhs: Shaped) -> Shaped {
        let shape: ValueShape? = switch (lhs.shape, rhs.shape) {
        case (nil, let other), (let other, nil): other
        case (let left?, let right?): merge(left, right)
        }
        return Shaped(shape: shape, isOptional: lhs.isOptional || rhs.isOptional)
    }

    // MARK: Private

    private static func required(_ shape: ValueShape) -> Shaped {
        Shaped(shape: shape, isOptional: false)
    }

    private static func mergeItems(_ merged: Shaped?, _ next: Shaped) -> Shaped? {
        merged.map { merge($0, next) } ?? next
    }

    private static func merge(_ lhs: ValueShape, _ rhs: ValueShape) -> ValueShape {
        switch (lhs, rhs) {
        case _ where lhs == rhs:
            lhs
        case (.int, .double), (.double, .int):
            .double
        case (.string, .date), (.date, .string), (.string, .url), (.url, .string), (.date, .url), (.url, .date):
            .string
        case (.object(let left), .object(let right)):
            .object(mergeFields(left, right))
        case (.array(let left), .array(let right)):
            .array(right.flatMap { mergeItems(left, $0) } ?? left)
        default:
            .mixed
        }
    }

    /// Keys in the order they first appear; a key one side lacks becomes optional.
    private static func mergeFields(_ left: [FieldShape], _ right: [FieldShape]) -> [FieldShape] {
        let rightByKey = Dictionary(right.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
        let leftKeys = Set(left.map(\.key))
        let merged = left.map { field in
            let value = rightByKey[field.key].map { merge(field.value, $0) } ?? optional(field.value)
            return FieldShape(key: field.key, value: value)
        }
        let added = right.filter { !leftKeys.contains($0.key) }.map { FieldShape(key: $0.key, value: optional($0.value)) }
        return merged + added
    }

    private static func optional(_ value: Shaped) -> Shaped {
        Shaped(shape: value.shape, isOptional: true)
    }

    /// Duplicate keys keep the place of the first and the value of the last, like the parser's source ranges.
    private static func fields(of members: [JSONMember], options: Options) -> [FieldShape] {
        var order: [String] = []
        var values: [String: Shaped] = [:]
        for member in members {
            if values[member.key] == nil { order.append(member.key) }
            values[member.key] = shape(of: member.value, options: options)
        }
        return order.compactMap { key in values[key].map { FieldShape(key: key, value: $0) } }
    }

    /// Whole numbers that fit in an `Int`; anything else (fractions, exponents, huge numbers) is a `Double`.
    private static func isInteger(_ literal: String) -> Bool {
        !literal.contains(where: { $0 == "." || $0 == "e" || $0 == "E" }) && Int(literal) != nil
    }

    private static func stringShape(_ text: String, options: Options) -> ValueShape {
        if options.detectsDates, dateFormatter.date(from: text) != nil {
            return .date
        }
        if options.detectsURLs, isWebAddress(text) {
            return .url
        }
        return .string
    }

    private static func isWebAddress(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        guard lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://"),
              let url = URL(string: text), let host = url.host(), !host.isEmpty
        else { return false }
        return true
    }
}
