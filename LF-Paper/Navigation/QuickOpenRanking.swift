//
//  QuickOpenRanking.swift
//  LF-Paper
//

import Foundation

/// One Quick Open result, with the file-name characters to highlight.
nonisolated struct QuickOpenResult: Identifiable, Equatable, Sendable {
    let file: IndexedFile
    let score: Int
    /// Offsets into `file.name` of the characters that matched the query.
    let nameMatchOffsets: [Int]

    var id: URL { file.url }
}

/// Orders files for Quick Open: best fuzzy match first, recently opened files ahead of close calls.
nonisolated enum QuickOpenRanking {
    /// The most recent file gets this much extra, the next one a little less, and so on.
    private static let recentBonus = 12

    static func rank(query: String, files: [IndexedFile], recent: [URL], limit: Int) -> [QuickOpenResult] {
        let recentRank = Dictionary(
            recent.enumerated().map { ($0.element.standardizedFileURL, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        let isEmptyQuery = query.allSatisfy(\.isWhitespace)

        let results: [(result: QuickOpenResult, recency: Int?)] = files.compactMap { file in
            guard let match = FuzzyMatcher.match(query, in: file.relativePath) else { return nil }
            let recency = recentRank[file.url.standardizedFileURL]
            let bonus = recency.map { max(recentBonus - $0, 1) } ?? 0
            let result = QuickOpenResult(
                file: file,
                score: match.score + (isEmptyQuery ? 0 : bonus),
                nameMatchOffsets: nameOffsets(of: match, in: file)
            )
            return (result, recency)
        }

        let ordered = results.sorted { lhs, rhs in
            if isEmptyQuery {
                // Recent files in the order they were opened, then everything else by path.
                switch (lhs.recency, rhs.recency) {
                case let (left?, right?): return left < right
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil): break
                }
            } else if lhs.result.score != rhs.result.score {
                return lhs.result.score > rhs.result.score
            }
            return isOrderedByPath(lhs.result.file, rhs.result.file)
        }
        return ordered.prefix(limit).map(\.result)
    }

    /// Shorter paths first (fewer folders to dig through), then alphabetically.
    private static func isOrderedByPath(_ lhs: IndexedFile, _ rhs: IndexedFile) -> Bool {
        if lhs.relativePath.count != rhs.relativePath.count, lhs.name == rhs.name {
            return lhs.relativePath.count < rhs.relativePath.count
        }
        return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
    }

    /// Matched offsets moved from the whole path into the file name, dropping those in folder names.
    private static func nameOffsets(of match: FuzzyMatch, in file: IndexedFile) -> [Int] {
        let nameStart = file.relativePath.count - file.name.count
        return match.matchedOffsets.filter { $0 >= nameStart }.map { $0 - nameStart }
    }
}
