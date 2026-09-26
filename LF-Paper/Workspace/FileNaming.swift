//
//  FileNaming.swift
//  LF-Paper
//

import Foundation

/// Rules for names the user types and names the app generates.
nonisolated enum FileNaming {
    private static let forbiddenCharacters = CharacterSet(charactersIn: "/:")
    private static let reservedNames: Set<String> = [".", ".."]

    /// Returns the trimmed name, or throws `.invalidName` if it can't be used as a file name.
    static func validate(_ name: String) throws(AppError) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !reservedNames.contains(trimmed),
              trimmed.rangeOfCharacter(from: forbiddenCharacters) == nil
        else {
            throw .invalidName(name)
        }
        return trimmed
    }

    /// "Untitled.md", then "Untitled 2.md", "Untitled 3.md", … — the first one not in `existing`.
    /// Comparison ignores case, matching the default macOS file system.
    static func uniqueName(base: String, fileExtension: String?, existing: Set<String>) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        var number = 1
        while true {
            let candidate = makeName(base: base, number: number, fileExtension: fileExtension)
            if !taken.contains(candidate.lowercased()) {
                return candidate
            }
            number += 1
        }
    }

    private static func makeName(base: String, number: Int, fileExtension: String?) -> String {
        let stem = number == 1 ? base : "\(base) \(number)"
        guard let fileExtension else { return stem }
        return "\(stem).\(fileExtension)"
    }
}
