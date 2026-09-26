//
//  FuzzyMatcher.swift
//  LF-Paper
//

/// How well a query matches a file path, and which characters of the path matched.
nonisolated struct FuzzyMatch: Equatable, Sendable {
    let score: Int
    /// Character offsets into the candidate, in order.
    let matchedOffsets: [Int]
}

/// Matches a query whose letters appear in order anywhere in a path ("rdm" matches "README.md"),
/// like Quick Open in Xcode or VS Code. Case and spaces in the query are ignored.
///
/// Every placement of the letters is scored and the best one wins: letters next to each other,
/// letters that start a word, and letters in the file name (rather than its folders) score higher;
/// gaps between letters cost a little.
nonisolated enum FuzzyMatcher {
    private static let letterScore = 1
    private static let consecutiveBonus = 10
    private static let wordStartBonus = 8
    private static let fileNameBonus = 5
    private static let maximumGapPenalty = 3
    private static let wordSeparators: Set<Character> = ["/", "-", "_", ".", " "]

    static func match(_ query: String, in candidate: String) -> FuzzyMatch? {
        let needle = Array(query.lowercased().filter { $0 != " " })
        guard !needle.isEmpty else { return FuzzyMatch(score: 0, matchedOffsets: []) }
        let original = Array(candidate)
        let haystack = original.map { Character($0.lowercased()) }
        guard isSubsequence(needle, of: haystack) else { return nil }

        let bonuses = positionBonuses(for: original)
        return bestPlacement(of: needle, in: haystack, bonuses: bonuses)
    }

    /// A fast check that rules out most candidates before the full scoring.
    private static func isSubsequence(_ needle: [Character], of haystack: [Character]) -> Bool {
        var remaining = needle[...]
        for character in haystack where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return false
    }

    /// What a letter at each position earns on its own: word starts and the file-name part.
    private static func positionBonuses(for characters: [Character]) -> [Int] {
        let fileNameStart = (characters.lastIndex(of: "/") ?? -1) + 1
        return characters.indices.map { index in
            var bonus = letterScore
            if isWordStart(index, in: characters) { bonus += wordStartBonus }
            if index >= fileNameStart { bonus += fileNameBonus }
            return bonus
        }
    }

    private static func isWordStart(_ index: Int, in characters: [Character]) -> Bool {
        guard index > 0 else { return true }
        let previous = characters[index - 1]
        let current = characters[index]
        return wordSeparators.contains(previous) || (previous.isLowercase && current.isUppercase)
    }

    /// Dynamic programming over (query letter, candidate position): `best[i][j]` is the highest score
    /// with query letter `i` placed at position `j`. Gaps longer than `maximumGapPenalty` all cost the
    /// same, so one running maximum covers them and the whole search is O(query × candidate).
    private static func bestPlacement(of needle: [Character], in haystack: [Character], bonuses: [Int]) -> FuzzyMatch? {
        let unreachable = Int.min / 2
        var best = Array(repeating: Array(repeating: unreachable, count: haystack.count), count: needle.count)
        var previousPosition = Array(repeating: Array(repeating: -1, count: haystack.count), count: needle.count)

        for (position, character) in haystack.enumerated() where character == needle[0] {
            best[0][position] = bonuses[position]
        }
        for letter in 1..<needle.count {
            var farBest = (score: unreachable, position: -1) // best earlier placement with the longest gap
            for position in letter..<haystack.count {
                let far = position - maximumGapPenalty - 1
                if far >= 0, best[letter - 1][far] > farBest.score {
                    farBest = (best[letter - 1][far], far)
                }
                guard haystack[position] == needle[letter] else { continue }

                var link = (score: farBest.score - maximumGapPenalty, position: farBest.position)
                for earlier in max(far + 1, letter - 1)..<position where best[letter - 1][earlier] > unreachable {
                    let gap = position - earlier - 1
                    let score = best[letter - 1][earlier] + (gap == 0 ? consecutiveBonus : -gap)
                    if score > link.score { link = (score, earlier) }
                }
                guard link.position >= 0, link.score > unreachable else { continue }
                best[letter][position] = link.score + bonuses[position]
                previousPosition[letter][position] = link.position
            }
        }

        let last = needle.count - 1
        guard let end = best[last].indices.max(by: { best[last][$0] < best[last][$1] }),
              best[last][end] > unreachable
        else { return nil }

        var offsets = [end]
        for letter in stride(from: last, to: 0, by: -1) {
            offsets.append(previousPosition[letter][offsets[offsets.count - 1]])
        }
        return FuzzyMatch(score: best[last][end], matchedOffsets: offsets.reversed())
    }
}
