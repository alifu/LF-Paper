//
//  ReplacePlan.swift
//  LF-Paper
//

import Foundation

/// One replacement: the match as the search found it, and the text that takes its place.
nonisolated struct ReplaceChange: Equatable, Sendable, Identifiable {
    let match: TextMatch
    let replacement: String

    var id: Int { match.id }

    /// The match's preview line with the replacement in place, and where the replacement is in it.
    var after: (text: String, range: NSRange) {
        let preview = match.preview as NSString
        let text = preview.replacingCharacters(in: match.previewRange, with: replacement)
        return (text, NSRange(location: match.previewRange.location, length: (replacement as NSString).length))
    }
}

/// Every replacement in one file, and the file's text before and after.
nonisolated struct FileReplacement: Equatable, Sendable, Identifiable {
    let file: IndexedFile
    let originalText: String
    let newText: String
    let changes: [ReplaceChange]

    var id: URL { file.url }
}

nonisolated enum ReplaceSkipReason: Equatable, Sendable, CustomStringConvertible {
    case changedSinceSearch
    /// Gone, too large, or not text.
    case unreadable
    case writeFailed(AppError)

    var description: String {
        switch self {
        case .changedSinceSearch: "changed since the search; search again"
        case .unreadable: "couldn’t be read"
        case .writeFailed(let error): error.errorDescription ?? "couldn’t be written"
        }
    }
}

/// A file Replace All left alone, and why.
nonisolated struct SkippedFile: Equatable, Sendable, Identifiable {
    let file: IndexedFile
    let reason: ReplaceSkipReason

    var id: URL { file.url }
}

/// What Replace All would do, worked out before anything is written: the new text of each
/// file with matches, and the files that can't be replaced.
nonisolated struct ReplacePlan: Equatable, Sendable {
    let files: [FileReplacement]
    let skipped: [SkippedFile]

    func replacementCount(excluding excluded: Set<URL>) -> Int {
        files.filter { !excluded.contains($0.id) }.reduce(0) { $0 + $1.changes.count }
    }

    func fileCount(excluding excluded: Set<URL>) -> Int {
        files.filter { !excluded.contains($0.id) }.count
    }

    /// Plans replacing every match of `query` in the searched files with `replacement`.
    /// `currentText` gives each file's text now (an open tab's, or the disk's); a file whose
    /// text isn't the one that was searched is skipped, so nothing unseen is replaced.
    static func make(
        results: [FileSearchResult],
        query: SearchQuery,
        replacement: String,
        currentText: (IndexedFile) -> String?
    ) throws(ReplaceError) -> ReplacePlan {
        let expression: NSRegularExpression
        do throws(SearchQueryError) {
            expression = try query.regularExpression()
        } catch {
            throw .query(error)
        }
        let template = try ReplaceTemplate.expressionTemplate(
            for: replacement,
            usesRegularExpression: query.options.usesRegularExpression,
            groupCount: expression.numberOfCaptureGroups
        )
        var files: [FileReplacement] = []
        var skipped: [SkippedFile] = []
        for result in results {
            // A cancelled preview (Cancel, a new preview, another folder) is thrown away; stop working on it.
            guard !Task.isCancelled else { break }
            guard let text = currentText(result.file) else {
                skipped.append(SkippedFile(file: result.file, reason: .unreadable))
                continue
            }
            guard TextFingerprint(text) == result.fingerprint else {
                skipped.append(SkippedFile(file: result.file, reason: .changedSinceSearch))
                continue
            }
            files.append(replacing(expression, with: template, in: text, of: result.file))
        }
        return ReplacePlan(files: files, skipped: skipped)
    }

    private static func replacing(_ expression: NSRegularExpression, with template: String, in text: String, of file: IndexedFile) -> FileReplacement {
        let string = text as NSString
        let lines = LineIndex(text: string)
        let newText = NSMutableString()
        var changes: [ReplaceChange] = []
        var copiedUpTo = 0
        // Empty matches are skipped, as in the search.
        for result in expression.matches(in: text, range: NSRange(location: 0, length: string.length)) where result.range.length > 0 {
            let replacement = expression.replacementString(for: result, in: text, offset: 0, template: template)
            newText.append(string.substring(with: NSRange(location: copiedUpTo, length: result.range.location - copiedUpTo)))
            newText.append(replacement)
            copiedUpTo = NSMaxRange(result.range)
            changes.append(ReplaceChange(match: TextSearch.match(at: result.range, in: string, lines: lines), replacement: replacement))
        }
        newText.append(string.substring(from: copiedUpTo))
        return FileReplacement(file: file, originalText: text, newText: newText as String, changes: changes)
    }
}
