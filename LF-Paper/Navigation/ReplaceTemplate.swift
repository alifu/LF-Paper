//
//  ReplaceTemplate.swift
//  LF-Paper
//

import Foundation

nonisolated enum ReplaceError: Error, Equatable, Sendable, LocalizedError {
    case query(SearchQueryError)
    /// A `$` that isn't followed by a group number.
    case missingGroupNumber
    case noSuchGroup(Int, available: Int)
    /// A `\` at the very end, escaping nothing.
    case trailingBackslash

    var errorDescription: String? {
        switch self {
        case .query(let error):
            error.errorDescription
        case .missingGroupNumber:
            "A “$” must be followed by a group number, such as $1. Write \\$ for a dollar sign."
        case .noSuchGroup(let group, let available):
            available == 0
                ? "There’s no group $\(group): the expression has no groups in parentheses."
                : "There’s no group $\(group): the expression has \(available) \(available == 1 ? "group" : "groups")."
        case .trailingBackslash:
            "The replacement ends with “\\”. Write \\\\ for a backslash."
        }
    }
}

/// Turns the Replace field into an `NSRegularExpression` template.
nonisolated enum ReplaceTemplate {
    /// Plain text is inserted literally. With regular expressions, `$1`… insert captured groups
    /// and `\` escapes the next character (`\$` is a dollar sign); anything else is an error.
    static func expressionTemplate(for replacement: String, usesRegularExpression: Bool, groupCount: Int) throws(ReplaceError) -> String {
        guard usesRegularExpression else {
            return NSRegularExpression.escapedTemplate(for: replacement)
        }
        try validate(replacement, groupCount: groupCount)
        return replacement
    }

    /// Checks the template the way `NSRegularExpression` reads it: `$` takes as many digits as
    /// still name an existing group, so with one group `$12` is group 1 followed by "2".
    private static func validate(_ template: String, groupCount: Int) throws(ReplaceError) {
        var characters = template.makeIterator()
        while let character = characters.next() {
            switch character {
            case "\\":
                guard characters.next() != nil else { throw .trailingBackslash }
            case "$":
                guard let digit = characters.next()?.wholeNumberValue else { throw .missingGroupNumber }
                guard digit <= groupCount else { throw .noSuchGroup(digit, available: groupCount) }
            default:
                continue
            }
        }
    }
}
