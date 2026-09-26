//
//  FolderSearchSession.swift
//  LF-Paper
//

import Foundation
import Observation

/// The state of Search in Folder for one window: the query, its options and the results so far.
@Observable
final class FolderSearchSession {
    /// Past this many matches the search stops, so a very common word can't flood memory.
    static let totalMatchLimit = 10_000

    var text = ""
    var options = SearchOptions()
    private(set) var results: [FileSearchResult] = []
    private(set) var isSearching = false
    private(set) var error: SearchQueryError?
    /// The text of the last search that ran, for the "No results for …" message.
    private(set) var searchedText: String?
    /// The search stopped at `totalMatchLimit`.
    private(set) var isTruncated = false
    /// The search in progress; tests await it.
    @ObservationIgnored private(set) var task: Task<Void, Never>?
    /// Only the latest search may change the state; a cancelled one can still be finishing.
    @ObservationIgnored private var currentSearchID: UUID?

    var matchCount: Int { results.reduce(0) { $0 + $1.matches.count } }

    /// Starts a new search (cancelling the one running). `targets` runs first, so it can wait for the file index.
    func start(targets: @escaping @MainActor () async -> [SearchTarget]) {
        cancel()
        let query = SearchQuery(text: text, options: options)
        do throws(SearchQueryError) {
            _ = try query.regularExpression()
        } catch {
            clearResults()
            self.error = error
            return
        }
        clearResults()
        searchedText = query.text
        isSearching = true
        let searchID = UUID()
        currentSearchID = searchID
        task = Task { [weak self] in
            let targets = await targets()
            for await result in FolderSearch.results(for: query, in: targets) {
                guard let self, self.currentSearchID == searchID, !Task.isCancelled else { return }
                self.results += [result]
                if self.matchCount >= Self.totalMatchLimit {
                    self.isTruncated = true
                    break
                }
            }
            guard let self, self.currentSearchID == searchID else { return }
            self.isSearching = false
        }
    }

    func cancel() {
        task?.cancel()
        currentSearchID = nil
        isSearching = false
    }

    /// Forgets the query's results, for example when another folder opens.
    func reset() {
        cancel()
        clearResults()
    }

    private func clearResults() {
        results = []
        error = nil
        searchedText = nil
        isTruncated = false
    }
}
