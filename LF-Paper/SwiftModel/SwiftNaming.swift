//
//  SwiftNaming.swift
//  LF-Paper
//

import Foundation

/// Turns JSON keys into Swift names: camelCase properties, UpperCamelCase types in the singular
/// for array items, keywords escaped with backticks.
nonisolated enum SwiftNaming {
    /// Words that need backticks to be used as a name.
    static let keywords: Set<String> = [
        "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init",
        "inout", "internal", "let", "open", "operator", "private", "precedencegroup", "protocol", "public",
        "rethrows", "static", "struct", "subscript", "typealias", "var", "break", "case", "catch", "continue",
        "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return", "throw",
        "switch", "where", "while", "Any", "as", "await", "false", "is", "nil", "self", "Self", "super", "throws",
        "true", "try", "Type", "Protocol",
    ]

    /// Type names that would hide a standard type (or the generated `JSONValue`); they get "Object" added.
    private static let reservedTypeNames: Set<String> = [
        "Any", "AnyObject", "Array", "Bool", "Character", "Codable", "CodingKey", "CodingKeys", "Data", "Date",
        "Decimal", "Decodable", "Decoder", "Dictionary", "Double", "Encodable", "Encoder", "Equatable", "Error",
        "Float", "Hashable", "Hasher", "Identifiable", "Int", "JSONValue", "Never", "Optional", "Protocol",
        "Range", "Result", "Self", "Sendable", "Set", "String", "Task", "Type", "URL", "UUID", "Void",
    ]

    private static let irregularPlurals: [String: String] = [
        "people": "person", "children": "child", "men": "man", "women": "woman", "mice": "mouse",
        "geese": "goose", "feet": "foot", "teeth": "tooth", "indices": "index", "criteria": "criterion",
    ]

    /// The property name for a JSON key, unescaped. With `.keep`, keys that are already valid Swift stay.
    static func propertyName(for key: String, style: SwiftModelOptions.KeyStyle) -> String {
        if style == .keep, isValidIdentifier(key) { return key }
        let words = self.words(in: key)
        guard let first = words.first else { return "value" }
        let head = first.allSatisfy(\.isUppercase) ? first.lowercased() : first.prefix(1).lowercased() + first.dropFirst()
        return startingWithALetter(head + words.dropFirst().map(capitalizingFirst).joined())
    }

    /// The type name for an object stored under `key`.
    static func typeName(for key: String) -> String {
        let name = startingWithALetter(words(in: key).map(capitalizingFirst).joined())
        guard !name.isEmpty else { return "Value" }
        return reservedTypeNames.contains(name) ? name + "Object" : name
    }

    /// The type name for the items of an array stored under `key`: "users" → "User".
    /// Words that have no singular form get "Item": "data" → "DataItem".
    static func elementTypeName(for key: String) -> String {
        let plural = startingWithALetter(words(in: key).map(capitalizingFirst).joined())
        let singular = singular(plural)
        return typeName(for: singular == plural || singular.isEmpty ? plural + "Item" : singular)
    }

    /// The root type's name from the JSON file's name: "users.json" → "User".
    static func rootTypeName(forFileNamed fileName: String) -> String {
        let base = fileName.lowercased().hasSuffix(".json") ? String(fileName.dropLast(5)) : (fileName as NSString).deletingPathExtension
        let name = startingWithALetter(words(in: base).map(capitalizingFirst).joined())
        guard !name.isEmpty else { return "Root" }
        return typeName(for: singular(name))
    }

    /// The last word of an UpperCamelCase name in the singular: "OrderItems" → "OrderItem".
    static func singular(_ name: String) -> String {
        let lastWordStart = name.lastIndex { $0.isUppercase } ?? name.startIndex
        let prefix = String(name[..<lastWordStart])
        let word = String(name[lastWordStart...])
        let lowercased = word.lowercased()
        if let irregular = irregularPlurals[lowercased] {
            return prefix + matchingCase(of: word, irregular)
        }
        let singular: String
        if lowercased.hasSuffix("ies"), word.count > 3 {
            singular = word.dropLast(3) + "y"
        } else if ["sses", "shes", "ches", "xes", "zes"].contains(where: lowercased.hasSuffix) {
            singular = String(word.dropLast(2))
        } else if ["ss", "us", "is"].contains(where: lowercased.hasSuffix) {
            singular = word
        } else if lowercased.hasSuffix("s"), word.count > 1 {
            singular = String(word.dropLast())
        } else {
            singular = word
        }
        return prefix + singular
    }

    /// The name, with backticks when it's a keyword.
    static func escaped(_ name: String) -> String {
        keywords.contains(name) ? "`\(name)`" : name
    }

    /// Letters, digits and underscores, not starting with a digit, and not a lone "_".
    static func isValidIdentifier(_ name: String) -> Bool {
        guard let first = name.first, name != "_", !first.isNumber else { return false }
        return name.allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
    }

    // MARK: Private

    /// Splits on anything that isn't a letter or digit; existing camelCase inside a word is kept.
    private static func words(in text: String) -> [String] {
        text.split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }

    private static func capitalizingFirst(_ word: String) -> String {
        word.prefix(1).uppercased() + word.dropFirst()
    }

    /// Names can't start with a digit: "2fa" → "_2fa".
    private static func startingWithALetter(_ name: String) -> String {
        name.first?.isNumber == true ? "_" + name : name
    }

    private static func matchingCase(of original: String, _ replacement: String) -> String {
        original.first?.isUppercase == true ? capitalizingFirst(replacement) : replacement
    }
}
