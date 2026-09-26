//
//  JSONParser.swift
//  LF-Paper
//

import Foundation

/// A strict RFC 8259 JSON parser (no comments, trailing commas or leading zeros; a leading BOM is
/// allowed). Works on UTF-16 so error positions and source ranges line up with `NSTextView`.
///
/// Iterative, not recursive: open containers live on an explicit stack, so deeply nested input
/// can't overflow a thread's call stack (background and test threads only get 512 KB).
nonisolated struct JSONParser {
    /// A sanity bound on nesting; real documents stay far below it.
    static let maximumDepth = 256

    static func parse(_ text: String, recordsSourceRanges: Bool = false) throws(JSONParseError) -> JSONDocument {
        var parser = JSONParser(units: Array(text.utf16), recordsSourceRanges: recordsSourceRanges)
        return try parser.parseDocument()
    }

    /// An object or array that has been opened but not yet closed.
    private nonisolated struct Frame {
        let isObject: Bool
        let start: Int
        let path: JSONPath
        var members: [JSONMember] = []
        var elements: [JSONValue] = []
        /// The key whose value is being parsed (objects only).
        var pendingKey = ""

        var closer: UInt16 { isObject ? Unit.closeBrace : Unit.closeBracket }
        var separatorOrCloser: String { isObject ? "',' or '}'" : "',' or ']'" }
        var value: JSONValue { isObject ? .object(members) : .array(elements) }
        var nextChildPath: JSONPath {
            isObject ? path.appending(.key(pendingKey)) : path.appending(.index(elements.count))
        }

        mutating func append(_ child: JSONValue) {
            if isObject {
                members.append(JSONMember(key: pendingKey, value: child))
            } else {
                elements.append(child)
            }
        }
    }

    private enum ValueStart {
        case complete(JSONValue)
        case opened(Frame)
    }

    private let units: [UInt16]
    private let recordsSourceRanges: Bool
    private var index = 0
    private var sourceRanges: [JSONPath: NSRange] = [:]

    private init(units: [UInt16], recordsSourceRanges: Bool) {
        self.units = units
        self.recordsSourceRanges = recordsSourceRanges
    }

    // MARK: Values

    private mutating func parseDocument() throws(JSONParseError) -> JSONDocument {
        if peek == Unit.byteOrderMark {
            index += 1
        }
        skipWhitespace()
        let value = try parseValue()
        skipWhitespace()
        guard index == units.count else { throw error(.trailingContent) }
        return JSONDocument(value: value, sourceRanges: sourceRanges)
    }

    private mutating func parseValue() throws(JSONParseError) -> JSONValue {
        var stack: [Frame] = []
        var path = JSONPath.root
        while true {
            // Read one value; an opened container waits on the stack for its children.
            var valueStart = index
            var value: JSONValue
            switch try readValueStart(depth: stack.count, path: path) {
            case .complete(let complete):
                value = complete
            case .opened(let frame):
                stack.append(frame)
                path = childPath(of: frame)
                continue
            }
            // Hand the value to its container, closing containers for as long as the text allows.
            while true {
                record(path, start: valueStart)
                guard var frame = stack.popLast() else { return value }
                frame.append(value)
                skipWhitespace()
                if consume(Unit.comma) {
                    skipWhitespace()
                    if frame.isObject {
                        frame.pendingKey = try parseKey()
                    }
                    stack.append(frame)
                    path = childPath(of: frame)
                    break
                }
                guard consume(frame.closer) else { throw unexpected(expected: frame.separatorOrCloser) }
                value = frame.value
                valueStart = frame.start
                path = frame.path
            }
        }
    }

    /// Reads a scalar or an empty container completely; for a non-empty container, reads up to
    /// its first child (and that child's key, for objects).
    private mutating func readValueStart(depth: Int, path: JSONPath) throws(JSONParseError) -> ValueStart {
        guard let unit = peek else { throw error(.unexpectedEnd(expected: "a value")) }
        switch unit {
        case Unit.openBrace, Unit.openBracket:
            guard depth < Self.maximumDepth else { throw error(.nestingTooDeep(limit: Self.maximumDepth)) }
            var frame = Frame(isObject: unit == Unit.openBrace, start: index, path: path)
            index += 1
            skipWhitespace()
            if consume(frame.closer) { return .complete(frame.value) }
            if frame.isObject {
                frame.pendingKey = try parseKey()
            }
            return .opened(frame)
        case Unit.quote:
            return .complete(.string(try parseString()))
        case Unit.lowerT:
            try expectLiteral("true")
            return .complete(.bool(true))
        case Unit.lowerF:
            try expectLiteral("false")
            return .complete(.bool(false))
        case Unit.lowerN:
            try expectLiteral("null")
            return .complete(.null)
        case Unit.minus, Unit.zero...Unit.nine:
            return .complete(.number(try parseNumber()))
        default:
            throw unexpected(expected: "a value")
        }
    }

    private mutating func parseKey() throws(JSONParseError) -> String {
        guard peek == Unit.quote else { throw unexpected(expected: "a string key") }
        let key = try parseString()
        skipWhitespace()
        guard consume(Unit.colon) else { throw unexpected(expected: "':' after the key") }
        skipWhitespace()
        return key
    }

    private func childPath(of frame: Frame) -> JSONPath {
        recordsSourceRanges ? frame.nextChildPath : .root
    }

    private mutating func record(_ path: JSONPath, start: Int) {
        guard recordsSourceRanges else { return }
        sourceRanges[path] = NSRange(location: start, length: index - start)
    }

    // MARK: Strings

    private mutating func parseString() throws(JSONParseError) -> String {
        let start = index
        index += 1 // opening quote
        var decoded: [UInt16] = []
        var runStart = index // characters without escapes are copied in runs
        while index < units.count {
            switch units[index] {
            case Unit.quote:
                decoded.append(contentsOf: units[runStart..<index])
                index += 1
                return String(decoding: decoded, as: UTF16.self)
            case Unit.backslash:
                decoded.append(contentsOf: units[runStart..<index])
                try parseEscape(into: &decoded)
                runStart = index
            case 0..<0x20:
                throw error(.unescapedControlCharacter)
            default:
                index += 1
            }
        }
        throw error(.unterminatedString, at: start)
    }

    private mutating func parseEscape(into decoded: inout [UInt16]) throws(JSONParseError) {
        let escapeStart = index
        index += 1 // backslash
        guard let unit = peek else { throw error(.invalidEscape, at: escapeStart) }
        index += 1
        switch unit {
        case Unit.quote, Unit.backslash, Unit.slash: decoded.append(unit)
        case Unit.lowerB: decoded.append(0x08)
        case Unit.lowerF: decoded.append(0x0C)
        case Unit.lowerN: decoded.append(0x0A)
        case Unit.lowerR: decoded.append(0x0D)
        case Unit.lowerT: decoded.append(0x09)
        case Unit.lowerU: decoded.append(try parseHexQuad(escapeStart: escapeStart))
        default: throw error(.invalidEscape, at: escapeStart)
        }
    }

    /// The four hex digits of `\uXXXX`. Surrogate pairs come out right because strings are UTF-16.
    private mutating func parseHexQuad(escapeStart: Int) throws(JSONParseError) -> UInt16 {
        guard index + 4 <= units.count else { throw error(.invalidEscape, at: escapeStart) }
        var value: UInt16 = 0
        for unit in units[index..<index + 4] {
            guard let digit = Self.hexValue(of: unit) else { throw error(.invalidEscape, at: escapeStart) }
            value = value << 4 | digit
        }
        index += 4
        return value
    }

    private static func hexValue(of unit: UInt16) -> UInt16? {
        switch unit {
        case Unit.zero...Unit.nine: unit - Unit.zero
        case Unit.lowerA...Unit.lowerF: unit - Unit.lowerA + 10
        case Unit.upperA...Unit.upperF: unit - Unit.upperA + 10
        default: nil
        }
    }

    // MARK: Numbers and literals

    /// `-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?`, kept as written.
    private mutating func parseNumber() throws(JSONParseError) -> JSONNumber {
        let start = index
        _ = consume(Unit.minus)
        if !consume(Unit.zero) {
            guard consumeDigits() > 0 else { throw error(.invalidNumber, at: start) }
        }
        if consume(Unit.dot) {
            guard consumeDigits() > 0 else { throw error(.invalidNumber, at: start) }
        }
        if consume(Unit.lowerE) || consume(Unit.upperE) {
            _ = consume(Unit.plus) || consume(Unit.minus)
            guard consumeDigits() > 0 else { throw error(.invalidNumber, at: start) }
        }
        return JSONNumber(literal: String(decoding: units[start..<index], as: UTF16.self))
    }

    private mutating func consumeDigits() -> Int {
        let start = index
        while let unit = peek, (Unit.zero...Unit.nine).contains(unit) {
            index += 1
        }
        return index - start
    }

    private mutating func expectLiteral(_ word: String) throws(JSONParseError) {
        let expected = Array(word.utf16)
        guard units[index...].starts(with: expected) else {
            throw error(.unexpectedCharacter(found: character(at: index), expected: word))
        }
        index += expected.count
    }

    // MARK: Scanning

    private var peek: UInt16? {
        index < units.count ? units[index] : nil
    }

    private mutating func consume(_ unit: UInt16) -> Bool {
        guard peek == unit else { return false }
        index += 1
        return true
    }

    private mutating func skipWhitespace() {
        while let unit = peek, unit == Unit.space || unit == Unit.tab || unit == Unit.lineFeed || unit == Unit.carriageReturn {
            index += 1
        }
    }

    // MARK: Errors

    private func error(_ reason: JSONParseError.Reason, at offset: Int? = nil) -> JSONParseError {
        JSONParseError(reason: reason, offset: offset ?? index, in: units)
    }

    /// "Expected X" at the current position, whether that's a wrong character or the end of the text.
    private func unexpected(expected: String) -> JSONParseError {
        guard index < units.count else { return error(.unexpectedEnd(expected: expected)) }
        return error(.unexpectedCharacter(found: character(at: index), expected: expected))
    }

    private func character(at offset: Int) -> String {
        String(decoding: [units[offset]], as: UTF16.self)
    }
}

/// UTF-16 code units the grammar cares about.
private nonisolated enum Unit {
    static let tab: UInt16 = 0x09
    static let lineFeed: UInt16 = 0x0A
    static let carriageReturn: UInt16 = 0x0D
    static let space: UInt16 = 0x20
    static let quote: UInt16 = 0x22
    static let plus: UInt16 = 0x2B
    static let comma: UInt16 = 0x2C
    static let minus: UInt16 = 0x2D
    static let dot: UInt16 = 0x2E
    static let slash: UInt16 = 0x2F
    static let zero: UInt16 = 0x30
    static let nine: UInt16 = 0x39
    static let colon: UInt16 = 0x3A
    static let upperA: UInt16 = 0x41
    static let upperE: UInt16 = 0x45
    static let upperF: UInt16 = 0x46
    static let openBracket: UInt16 = 0x5B
    static let backslash: UInt16 = 0x5C
    static let closeBracket: UInt16 = 0x5D
    static let lowerA: UInt16 = 0x61
    static let lowerB: UInt16 = 0x62
    static let lowerE: UInt16 = 0x65
    static let lowerF: UInt16 = 0x66
    static let lowerN: UInt16 = 0x6E
    static let lowerR: UInt16 = 0x72
    static let lowerT: UInt16 = 0x74
    static let lowerU: UInt16 = 0x75
    static let openBrace: UInt16 = 0x7B
    static let closeBrace: UInt16 = 0x7D
    static let byteOrderMark: UInt16 = 0xFEFF
}
