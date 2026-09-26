//
//  JSONTreeFilter.swift
//  LF-Paper
//

import Foundation

/// Which tree rows to show for a search: every match, the path down to it, and everything
/// inside a container whose key matches.
nonisolated enum JSONTreeFilter {
    /// `nil` for a blank query (show everything); otherwise the visible paths, possibly none.
    static func visiblePaths(in value: JSONValue, matching query: String) -> Set<JSONPath>? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        var visible: Set<JSONPath> = []
        _ = collect(value, at: .root, key: nil, needle: needle, into: &visible)
        return visible
    }

    /// Adds matches at or below `path` to `visible`; returns whether there were any.
    private static func collect(
        _ value: JSONValue,
        at path: JSONPath,
        key: String?,
        needle: String,
        into visible: inout Set<JSONPath>
    ) -> Bool {
        if let key, matches(key, needle) {
            insertAll(value, at: path, into: &visible)
            return true
        }
        var found = false
        switch value {
        case .object(let members):
            for member in members {
                let childFound = collect(member.value, at: path.appending(.key(member.key)), key: member.key, needle: needle, into: &visible)
                found = found || childFound
            }
        case .array(let elements):
            for (index, element) in elements.enumerated() {
                let childFound = collect(element, at: path.appending(.index(index)), key: nil, needle: needle, into: &visible)
                found = found || childFound
            }
        case .string(let text):
            found = matches(text, needle)
        case .number(let number):
            found = matches(number.literal, needle)
        case .bool(let flag):
            found = matches(flag ? "true" : "false", needle)
        case .null:
            found = matches("null", needle)
        }
        if found {
            visible.insert(path)
        }
        return found
    }

    private static func insertAll(_ value: JSONValue, at path: JSONPath, into visible: inout Set<JSONPath>) {
        visible.insert(path)
        switch value {
        case .object(let members):
            for member in members {
                insertAll(member.value, at: path.appending(.key(member.key)), into: &visible)
            }
        case .array(let elements):
            for (index, element) in elements.enumerated() {
                insertAll(element, at: path.appending(.index(index)), into: &visible)
            }
        case .string, .number, .bool, .null:
            break
        }
    }

    private static func matches(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
