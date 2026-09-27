//
//  FolderSearch.swift
//  LF-Paper
//

import Foundation

/// A file to search, with its unsaved text when it's open with edits.
nonisolated struct SearchTarget: Sendable {
    let file: IndexedFile
    let unsavedText: String?
}

/// Identifies a text, so Replace All can tell whether a file changed since it was searched.
nonisolated struct TextFingerprint: Hashable, Sendable {
    let length: Int
    let hash: Int

    init(_ text: String) {
        length = text.utf16.count
        hash = text.hashValue // stable within one run of the app, which is all it's used for
    }
}

/// Every match in one file.
nonisolated struct FileSearchResult: Equatable, Sendable, Identifiable {
    let file: IndexedFile
    let matches: [TextMatch]
    /// The text that was searched.
    let fingerprint: TextFingerprint

    var id: URL { file.url }
}

/// Searches many files off the main thread, one result per file with matches.
nonisolated enum FolderSearch {
    /// Bigger files (such as data dumps) are skipped to keep searching quick.
    static let defaultMaximumFileSize = 5_000_000
    static let matchesPerFileLimit = 1_000

    /// Results arrive as each file is searched. Stopping the iteration cancels the search.
    static func results(for query: SearchQuery, in targets: [SearchTarget]) -> AsyncStream<FileSearchResult> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                defer { continuation.finish() }
                guard let expression = try? query.regularExpression() else { return }
                for target in targets {
                    guard !Task.isCancelled else { return }
                    if let result = search(target, for: expression) {
                        continuation.yield(result)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// `nil` when the file has no matches or is skipped (too large, unreadable or not text).
    static func search(
        _ target: SearchTarget,
        for expression: NSRegularExpression,
        maximumFileSize: Int = defaultMaximumFileSize
    ) -> FileSearchResult? {
        guard let text = target.unsavedText ?? readText(of: target.file.url, maximumSize: maximumFileSize) else { return nil }
        let matches = TextSearch.matches(of: expression, in: text, limit: matchesPerFileLimit)
        return matches.isEmpty ? nil : FileSearchResult(file: target.file, matches: matches, fingerprint: TextFingerprint(text))
    }

    /// The file's text, or `nil` when it's too large, unreadable or not text.
    static func readText(of url: URL, maximumSize: Int = defaultMaximumFileSize) -> String? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= maximumSize,
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.contains("\u{0}")
        else { return nil }
        return text
    }
}
