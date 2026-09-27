//
//  JSONTreeSearch.swift
//  LF-Paper
//

import Foundation

/// What the tree pane's search field shows. Text starting with `$` is a JSONPath query;
/// anything else filters keys and values as before (`JSONTreeFilter`).
nonisolated enum JSONTreeSearch {
    nonisolated struct Result: Equatable, Sendable {
        /// `nil` shows the whole tree.
        let visiblePaths: Set<JSONPath>?
        /// What a query found, in order; empty for text filters.
        let matches: [JSONPath]
        /// `nil` for text filters, which don't count.
        let matchCount: Int?
        let error: JSONPathQueryError?

        static let everything = Result(visiblePaths: nil, matches: [], matchCount: nil, error: nil)
    }

    static func result(for query: String, in value: JSONValue) -> Result {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .everything }
        guard trimmed.hasPrefix("$") else {
            return Result(visiblePaths: JSONTreeFilter.visiblePaths(in: value, matching: trimmed), matches: [], matchCount: nil, error: nil)
        }
        do throws(JSONPathQueryError) {
            let matches = try JSONPathQuery.parse(trimmed).evaluate(on: value)
            return Result(
                visiblePaths: visiblePaths(for: matches),
                matches: matches.map(\.path),
                matchCount: matches.count,
                error: nil
            )
        } catch {
            return Result(visiblePaths: nil, matches: [], matchCount: nil, error: error)
        }
    }

    /// Each match, the way down to it, and everything inside it (so matched objects can be opened).
    private static func visiblePaths(for matches: [JSONPathMatch]) -> Set<JSONPath> {
        var visible: Set<JSONPath> = []
        for match in matches {
            for depth in 0...match.path.components.count {
                visible.insert(JSONPath(components: Array(match.path.components.prefix(depth))))
            }
            insertDescendants(of: match.value, at: match.path, into: &visible)
        }
        return visible
    }

    private static func insertDescendants(of value: JSONValue, at path: JSONPath, into visible: inout Set<JSONPath>) {
        switch value {
        case .object(let members):
            for member in members {
                let child = path.appending(.key(member.key))
                visible.insert(child)
                insertDescendants(of: member.value, at: child, into: &visible)
            }
        case .array(let elements):
            for (index, element) in elements.enumerated() {
                let child = path.appending(.index(index))
                visible.insert(child)
                insertDescendants(of: element, at: child, into: &visible)
            }
        case .string, .number, .bool, .null:
            break
        }
    }
}
