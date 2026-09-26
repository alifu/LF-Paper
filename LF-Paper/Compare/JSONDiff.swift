//
//  JSONDiff.swift
//  LF-Paper
//

import Foundation

/// One structural difference between two JSON documents.
nonisolated struct JSONDifference: Equatable, Sendable, CustomStringConvertible {
    nonisolated enum Kind: Equatable, Sendable {
        case added, removed, changed
    }

    let path: JSONPath
    let kind: Kind
    let oldValue: JSONValue?
    let newValue: JSONValue?

    /// `~ $.a: 1 → 2`, `+ $.b: true`, `- $.c: null` (values minified).
    var description: String {
        switch kind {
        case .added: "+ \(path): \(Self.text(of: newValue))"
        case .removed: "- \(path): \(Self.text(of: oldValue))"
        case .changed: "~ \(path): \(Self.text(of: oldValue)) → \(Self.text(of: newValue))"
        }
    }

    static func text(of value: JSONValue?) -> String {
        value.map { JSONFormatter.minified($0) } ?? ""
    }
}

/// Structural comparison: key order doesn't matter, numbers compare by value, and arrays compare
/// by index or — to survive insertions — by an identifying key such as `id`.
nonisolated enum JSONDiff {
    /// Beyond this many digits `Decimal` would round, so numbers are compared as written instead.
    private static let maximumExactDigits = 38
    private static let numberLocale = Locale(identifier: "en_US_POSIX")

    static func differences(from old: JSONValue, to new: JSONValue, arrayMatchKey: String? = nil) -> [JSONDifference] {
        var result: [JSONDifference] = []
        compare(old, new, at: .root, arrayMatchKey: arrayMatchKey, into: &result)
        return result
    }

    private static func compare(
        _ old: JSONValue,
        _ new: JSONValue,
        at path: JSONPath,
        arrayMatchKey: String?,
        into result: inout [JSONDifference]
    ) {
        switch (old, new) {
        case (.object(let oldMembers), .object(let newMembers)):
            compareObjects(oldMembers, newMembers, at: path, arrayMatchKey: arrayMatchKey, into: &result)
        case (.array(let oldElements), .array(let newElements)):
            if let key = arrayMatchKey,
               let oldIDs = identities(of: oldElements, key: key),
               let newIDs = identities(of: newElements, key: key) {
                compareByIdentity(oldElements, oldIDs, newElements, newIDs, at: path, arrayMatchKey: arrayMatchKey, into: &result)
            } else {
                compareByIndex(oldElements, newElements, at: path, arrayMatchKey: arrayMatchKey, into: &result)
            }
        default:
            if !scalarsEqual(old, new) {
                result.append(JSONDifference(path: path, kind: .changed, oldValue: old, newValue: new))
            }
        }
    }

    // MARK: Objects

    /// With duplicate keys the last value counts, as in most JSON readers.
    private static func compareObjects(
        _ old: [JSONMember],
        _ new: [JSONMember],
        at path: JSONPath,
        arrayMatchKey: String?,
        into result: inout [JSONDifference]
    ) {
        let oldValues = lastValues(of: old)
        let newValues = lastValues(of: new)
        for key in uniqueKeys(of: old) {
            guard let oldValue = oldValues[key] else { continue }
            let childPath = path.appending(.key(key))
            if let newValue = newValues[key] {
                compare(oldValue, newValue, at: childPath, arrayMatchKey: arrayMatchKey, into: &result)
            } else {
                result.append(JSONDifference(path: childPath, kind: .removed, oldValue: oldValue, newValue: nil))
            }
        }
        for key in uniqueKeys(of: new) where oldValues[key] == nil {
            guard let newValue = newValues[key] else { continue }
            result.append(JSONDifference(path: path.appending(.key(key)), kind: .added, oldValue: nil, newValue: newValue))
        }
    }

    private static func lastValues(of members: [JSONMember]) -> [String: JSONValue] {
        Dictionary(members.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
    }

    /// Keys in order of first appearance.
    private static func uniqueKeys(of members: [JSONMember]) -> [String] {
        var seen: Set<String> = []
        return members.compactMap { seen.insert($0.key).inserted ? $0.key : nil }
    }

    // MARK: Arrays

    private static func compareByIndex(
        _ old: [JSONValue],
        _ new: [JSONValue],
        at path: JSONPath,
        arrayMatchKey: String?,
        into result: inout [JSONDifference]
    ) {
        for index in 0..<max(old.count, new.count) {
            let childPath = path.appending(.index(index))
            switch (index < old.count, index < new.count) {
            case (true, true):
                compare(old[index], new[index], at: childPath, arrayMatchKey: arrayMatchKey, into: &result)
            case (true, false):
                result.append(JSONDifference(path: childPath, kind: .removed, oldValue: old[index], newValue: nil))
            case (false, true):
                result.append(JSONDifference(path: childPath, kind: .added, oldValue: nil, newValue: new[index]))
            case (false, false):
                break
            }
        }
    }

    /// Items are paired by their key's value. Changes and additions use the new index; removals the old one.
    private static func compareByIdentity(
        _ old: [JSONValue], _ oldIDs: [String],
        _ new: [JSONValue], _ newIDs: [String],
        at path: JSONPath,
        arrayMatchKey: String?,
        into result: inout [JSONDifference]
    ) {
        let newIndexByID = Dictionary(uniqueKeysWithValues: newIDs.enumerated().map { ($1, $0) })
        let oldIDSet = Set(oldIDs)
        for (oldIndex, id) in oldIDs.enumerated() {
            if let newIndex = newIndexByID[id] {
                compare(old[oldIndex], new[newIndex], at: path.appending(.index(newIndex)), arrayMatchKey: arrayMatchKey, into: &result)
            } else {
                result.append(JSONDifference(path: path.appending(.index(oldIndex)), kind: .removed, oldValue: old[oldIndex], newValue: nil))
            }
        }
        for (newIndex, id) in newIDs.enumerated() where !oldIDSet.contains(id) {
            result.append(JSONDifference(path: path.appending(.index(newIndex)), kind: .added, oldValue: nil, newValue: new[newIndex]))
        }
    }

    /// Each item's key value, or `nil` if any item isn't an object with the key or two share a value.
    private static func identities(of elements: [JSONValue], key: String) -> [String]? {
        var ids: [String] = []
        for element in elements {
            guard case .object(let members) = element,
                  let id = members.last(where: { $0.key == key })?.value
            else { return nil }
            ids.append(JSONFormatter.minified(id))
        }
        return Set(ids).count == ids.count ? ids : nil
    }

    // MARK: Scalars

    private static func scalarsEqual(_ old: JSONValue, _ new: JSONValue) -> Bool {
        if case .number(let oldNumber) = old, case .number(let newNumber) = new {
            return numbersEqual(oldNumber, newNumber)
        }
        return old == new
    }

    /// `1.0 == 1 == 1e0`; numbers too big or too precise for `Decimal` compare as written.
    private static func numbersEqual(_ lhs: JSONNumber, _ rhs: JSONNumber) -> Bool {
        if lhs.literal == rhs.literal { return true }
        guard let left = exactDecimal(lhs), let right = exactDecimal(rhs) else { return false }
        return left == right
    }

    private static func exactDecimal(_ number: JSONNumber) -> Decimal? {
        guard number.literal.filter(\.isWholeNumber).count <= maximumExactDigits,
              let value = Decimal(string: number.literal, locale: numberLocale),
              !value.isNaN
        else { return nil }
        return value
    }
}
