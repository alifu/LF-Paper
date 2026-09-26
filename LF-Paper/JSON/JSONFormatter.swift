//
//  JSONFormatter.swift
//  LF-Paper
//

import Foundation

/// Writes a `JSONValue` back to text: pretty-printed or minified, keys in their original
/// order or sorted, numbers exactly as they were written.
nonisolated enum JSONFormatter {
    nonisolated enum Indentation: Equatable, Sendable {
        case spaces(Int)
        case tab

        fileprivate var unit: String {
            switch self {
            case .spaces(let count): String(repeating: " ", count: max(count, 0))
            case .tab: "\t"
            }
        }
    }

    static func pretty(_ value: JSONValue, indentation: Indentation = .spaces(2), sortsKeys: Bool = false) -> String {
        var writer = Writer(indentUnit: indentation.unit, sortsKeys: sortsKeys)
        writer.write(value, level: 0)
        return writer.output
    }

    static func minified(_ value: JSONValue, sortsKeys: Bool = false) -> String {
        var writer = Writer(indentUnit: nil, sortsKeys: sortsKeys)
        writer.write(value, level: 0)
        return writer.output
    }

    /// A JSON string literal: quotes, backslashes and control characters escaped; everything else as-is.
    static func quoted(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{08}": result += "\\b"
            case "\u{0C}": result += "\\f"
            case _ where scalar.value < 0x20: result += "\\u" + fourDigitHex(scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }

    private static func fourDigitHex(_ value: UInt32) -> String {
        let hex = String(value, radix: 16)
        return String(repeating: "0", count: max(4 - hex.count, 0)) + hex
    }
}

private nonisolated struct Writer {
    /// `nil` writes everything on one line with no spaces.
    let indentUnit: String?
    let sortsKeys: Bool
    private(set) var output = ""

    init(indentUnit: String?, sortsKeys: Bool) {
        self.indentUnit = indentUnit
        self.sortsKeys = sortsKeys
    }

    mutating func write(_ value: JSONValue, level: Int) {
        switch value {
        case .object(let members): writeObject(members, level: level)
        case .array(let elements): writeArray(elements, level: level)
        case .string(let text): output += JSONFormatter.quoted(text)
        case .number(let number): output += number.literal
        case .bool(let flag): output += flag ? "true" : "false"
        case .null: output += "null"
        }
    }

    private mutating func writeObject(_ members: [JSONMember], level: Int) {
        guard !members.isEmpty else {
            output += "{}"
            return
        }
        // Swift's sort is stable, so duplicate keys keep their relative order.
        let ordered = sortsKeys ? members.sorted { $0.key < $1.key } : members
        output += "{"
        for (position, member) in ordered.enumerated() {
            if position > 0 { output += "," }
            startLine(level: level + 1)
            output += JSONFormatter.quoted(member.key)
            output += indentUnit == nil ? ":" : ": "
            write(member.value, level: level + 1)
        }
        startLine(level: level)
        output += "}"
    }

    private mutating func writeArray(_ elements: [JSONValue], level: Int) {
        guard !elements.isEmpty else {
            output += "[]"
            return
        }
        output += "["
        for (position, element) in elements.enumerated() {
            if position > 0 { output += "," }
            startLine(level: level + 1)
            write(element, level: level + 1)
        }
        startLine(level: level)
        output += "]"
    }

    private mutating func startLine(level: Int) {
        guard let indentUnit else { return }
        output += "\n" + String(repeating: indentUnit, count: level)
    }
}
