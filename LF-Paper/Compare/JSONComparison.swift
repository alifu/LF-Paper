//
//  JSONComparison.swift
//  LF-Paper
//

import Foundation

/// Compares two JSON texts: structural differences plus a side-by-side line diff of both
/// documents formatted the same way (so whitespace never shows up as a change).
nonisolated enum JSONComparison {
    nonisolated enum Side: Equatable, Sendable {
        case left, right
    }

    nonisolated struct Options: Equatable, Sendable {
        /// Sort keys before the line diff, so reordered keys don't show as changes.
        var ignoresKeyOrder = true
        /// Match array items by this key instead of by position (structural diff only).
        var arrayMatchKey: String?
    }

    nonisolated struct Result: Equatable, Sendable {
        let differences: [JSONDifference]
        let rows: [SideBySideRow]
        let changeStarts: [Int]
    }

    nonisolated enum Outcome: Equatable, Sendable {
        /// One or both sides are missing.
        case incomplete
        case invalid(Side, JSONParseError)
        case compared(Result)
    }

    static func run(left: String?, right: String?, options: Options) -> Outcome {
        guard let left, let right else { return .incomplete }
        let leftValue: JSONValue
        let rightValue: JSONValue
        do throws(JSONParseError) {
            leftValue = try JSONParser.parse(left).value
        } catch {
            return .invalid(.left, error)
        }
        do throws(JSONParseError) {
            rightValue = try JSONParser.parse(right).value
        } catch {
            return .invalid(.right, error)
        }

        let differences = JSONDiff.differences(from: leftValue, to: rightValue, arrayMatchKey: options.arrayMatchKey)
        let lines = TextDiff.lines(
            from: JSONFormatter.pretty(leftValue, sortsKeys: options.ignoresKeyOrder),
            to: JSONFormatter.pretty(rightValue, sortsKeys: options.ignoresKeyOrder)
        )
        let rows = SideBySideRows.make(from: lines)
        return .compared(Result(differences: differences, rows: rows, changeStarts: SideBySideRows.changeStarts(in: rows)))
    }

    /// Same as `run`, off the main thread.
    @concurrent
    static func runInBackground(left: String?, right: String?, options: Options) async -> Outcome {
        run(left: left, right: right, options: options)
    }
}
