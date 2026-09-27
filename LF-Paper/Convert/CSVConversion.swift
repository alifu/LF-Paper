//
//  CSVConversion.swift
//  LF-Paper
//

import Foundation

/// CSV (RFC 4180) ↔ JSON: an array of flat objects ↔ a header row and one row per object.
/// Reading CSV, numbers (in JSON's syntax, so "01234" stays text) and `true`/`false` become
/// JSON numbers and booleans; everything else, including empty fields, stays a string.
nonisolated enum CSVConversion {
    // MARK: CSV → JSON

    static func json(fromCSV csv: String) throws(ConversionError) -> JSONValue {
        let rows = try rows(fromCSV: csv)
        guard let header = rows.first else { return .array([]) }
        var objects: [JSONValue] = []
        for (index, row) in rows.dropFirst().enumerated() {
            guard row.count <= header.count else {
                throw ConversionError(message: "Row \(index + 2) has \(row.count) fields, but the header has \(header.count).")
            }
            let fields = row + Array(repeating: "", count: header.count - row.count)
            objects.append(.object(zip(header, fields).map { JSONMember(key: $0, value: value(of: $1)) }))
        }
        return .array(objects)
    }

    /// Rows of fields. Quoted fields may hold commas, line breaks and doubled quotes (`""`).
    /// Lines end with `\n` or `\r\n`; a final line break doesn't start another row.
    static func rows(fromCSV csv: String) throws(ConversionError) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var fieldWasQuoted = false
        var characters = csv.makeIterator()
        var pending: Character?

        func finishField() {
            row.append(field)
            field = ""
            fieldWasQuoted = false
        }
        func finishRow() {
            finishField()
            rows.append(row)
            row = []
        }

        while let character = pending ?? characters.next() {
            pending = nil
            if isQuoted {
                if character == "\"" {
                    let next = characters.next()
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        isQuoted = false
                        pending = next
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"" where field.isEmpty && !fieldWasQuoted:
                isQuoted = true
                fieldWasQuoted = true
            case ",":
                finishField()
            case "\n", "\r\n", "\r":
                finishRow()
            default:
                field.append(character)
            }
        }
        guard !isQuoted else { throw ConversionError(message: "A quoted field is never closed.") }
        if !field.isEmpty || fieldWasQuoted || !row.isEmpty {
            finishRow()
        }
        return rows
    }

    private static func value(of field: String) -> JSONValue {
        if field == "true" { return .bool(true) }
        if field == "false" { return .bool(false) }
        if JSONNumberLiteral.isValid(field) { return .number(JSONNumber(literal: field)) }
        return .string(field)
    }

    // MARK: JSON → CSV

    /// The header is every key, in the order first seen. Missing values and `null` are empty.
    static func csv(from value: JSONValue) throws(ConversionError) -> String {
        guard case .array(let items) = value else {
            throw ConversionError(message: "Only a list of objects can become CSV; this is a single value.")
        }
        var header: [String] = []
        var rows: [[String: String]] = []
        for (index, item) in items.enumerated() {
            guard case .object(let members) = item else {
                throw ConversionError(message: "Item [\(index)] isn’t an object; CSV needs a list of objects.")
            }
            var row: [String: String] = [:]
            for member in members {
                if !header.contains(member.key) { header.append(member.key) }
                row[member.key] = try field(member.value, key: member.key, index: index)
            }
            rows.append(row)
        }
        guard !header.isEmpty else { return "" }
        let lines = [header.map(quoted)] + rows.map { row in header.map { quoted(row[$0] ?? "") } }
        return lines.map { $0.joined(separator: ",") + "\r\n" }.joined()
    }

    private static func field(_ value: JSONValue, key: String, index: Int) throws(ConversionError) -> String {
        switch value {
        case .string(let text): return text
        case .number(let number): return number.literal
        case .bool(let flag): return flag ? "true" : "false"
        case .null: return ""
        case .object, .array:
            throw ConversionError(message: "Item [\(index)] has a list or object in “\(key)”; CSV can only hold plain values.")
        }
    }

    /// Quotes a field that holds a comma, quote or line break, or starts or ends with a space.
    private static func quoted(_ field: String) -> String {
        let needsQuotes = field.contains { $0 == "," || $0 == "\"" || $0.isNewline }
            || field.first?.isWhitespace == true || field.last?.isWhitespace == true
        return needsQuotes ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : field
    }
}
