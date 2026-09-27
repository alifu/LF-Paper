//
//  ReplacePlanTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

/// What Replace All would change, worked out from the search results before anything is written.
struct ReplacePlanTests {
    private let root = URL(filePath: "/tmp/root", directoryHint: .isDirectory)

    private func file(_ path: String) -> IndexedFile {
        IndexedFile(root: root, relativePath: path)! // every test path is a Markdown file
    }

    /// Searches `texts` like Find in Folder does, then plans the replacement against `current` (or the same texts).
    private func plan(
        _ texts: [String: String],
        find: String,
        replace: String,
        options: SearchOptions = SearchOptions(),
        current: [String: String]? = nil
    ) throws(ReplaceError) -> ReplacePlan {
        let query = SearchQuery(text: find, options: options)
        guard let expression = try? query.regularExpression() else { throw .query(.emptyQuery) }
        let results = texts.keys.sorted().compactMap { path in
            FolderSearch.search(SearchTarget(file: file(path), unsavedText: texts[path]), for: expression)
        }
        let now = current ?? texts
        return try ReplacePlan.make(results: results, query: query, replacement: replace) { now[$0.relativePath] }
    }

    // MARK: Replacement text

    @Test func plainTextIsReplacedLiterally() throws {
        let plan = try plan(["a.md": "cost: $1 (a.b)"], find: "$1 (a.b)", replace: #"$2 \n"#)

        #expect(plan.files.first?.newText == #"cost: $2 \n"#)
    }

    @Test func plainTextIgnoresCaseUnlessAsked() throws {
        let loose = try plan(["a.md": "Cat cat CAT"], find: "cat", replace: "dog")
        let strict = try plan(["a.md": "Cat cat CAT"], find: "cat", replace: "dog", options: SearchOptions(matchesCase: true))

        #expect(loose.files.first?.newText == "dog dog dog")
        #expect(strict.files.first?.newText == "Cat dog CAT")
    }

    @Test func wholeWordsLeaveLongerWordsAlone() throws {
        let plan = try plan(["a.md": "cat catalog cat."], find: "cat", replace: "dog", options: SearchOptions(matchesWholeWord: true))

        #expect(plan.files.first?.newText == "dog catalog dog.")
    }

    @Test func regularExpressionsInsertCapturedGroups() throws {
        let plan = try plan(["a.md": "2026-09-27"], find: #"(\d+)-(\d+)-(\d+)"#, replace: "$3/$2/$1 ($0)", options: SearchOptions(usesRegularExpression: true))

        #expect(plan.files.first?.newText == "27/09/2026 (2026-09-27)")
    }

    @Test func escapedDollarAndBackslashAreLiteral() throws {
        let plan = try plan(["a.md": "price 5"], find: #"price (\d)"#, replace: #"\$$1 \\"#, options: SearchOptions(usesRegularExpression: true))

        #expect(plan.files.first?.newText == #"$5 \"#)
    }

    @Test func groupNumbersUseOnlyTheDigitsThatNameAGroup() throws {
        // One group: "$12" is group 1 followed by "2".
        let plan = try plan(["a.md": "x"], find: "(x)", replace: "$12", options: SearchOptions(usesRegularExpression: true))

        #expect(plan.files.first?.newText == "x2")
    }

    @Test(arguments: [
        ("$", ReplaceError.missingGroupNumber),
        ("a$b", .missingGroupNumber),
        ("$2", .noSuchGroup(2, available: 1)),
        (#"end\"#, .trailingBackslash),
    ])
    func invalidTemplatesAreExplained(template: String, error: ReplaceError) {
        #expect(throws: error) {
            try plan(["a.md": "x"], find: "(x)", replace: template, options: SearchOptions(usesRegularExpression: true))
        }
        #expect(error.errorDescription?.isEmpty == false)
    }

    @Test func plainTextTemplatesAreNeverInvalid() throws {
        let plan = try plan(["a.md": "x"], find: "x", replace: #"$ \"#)

        #expect(plan.files.first?.newText == #"$ \"#)
    }

    @Test func anInvalidQueryIsReported() {
        let query = SearchQuery(text: "(", options: SearchOptions(usesRegularExpression: true))

        #expect(throws: ReplaceError.query(.invalidPattern("("))) {
            try ReplacePlan.make(results: [], query: query, replacement: "") { _ in nil }
        }
    }

    // MARK: Changes and counts

    @Test func eachChangeShowsItsLineBeforeAndAfter() throws {
        let plan = try plan(["a.md": "first line\n  second cat line\n"], find: "cat", replace: "dog")
        let change = try #require(plan.files.first?.changes.first)

        #expect(change.match.lineNumber == 2)
        #expect(change.match.preview == "second cat line")
        #expect((change.match.preview as NSString).substring(with: change.match.previewRange) == "cat")
        #expect(change.after.text == "second dog line")
        #expect((change.after.text as NSString).substring(with: change.after.range) == "dog")
    }

    @Test func countsReplacementsAndFiles() throws {
        let plan = try plan(["a.md": "x x", "b.md": "x", "c.md": "none"], find: "x", replace: "y")

        #expect(plan.files.map(\.file.relativePath) == ["a.md", "b.md"])
        #expect(plan.files.map(\.changes.count) == [2, 1])
        #expect(plan.replacementCount(excluding: []) == 3)
        #expect(plan.fileCount(excluding: []) == 2)
        #expect(plan.skipped.isEmpty)
    }

    @Test func leftOutFilesDontCount() throws {
        let plan = try plan(["a.md": "x x", "b.md": "x"], find: "x", replace: "y")
        let a = try #require(plan.files.first).file.url

        #expect(plan.replacementCount(excluding: [a]) == 1)
        #expect(plan.fileCount(excluding: [a]) == 1)
    }

    @Test func replacingWithTheSameTextChangesNothingButStillCounts() throws {
        let plan = try plan(["a.md": "x"], find: "x", replace: "x")

        #expect(plan.files.first?.newText == "x")
        #expect(plan.replacementCount(excluding: []) == 1)
    }

    @Test func worksWithTextBeyondTheBasicPlane() throws {
        let plan = try plan(["a.md": "😀 cat 😀 cat"], find: "cat", replace: "🐶")

        #expect(plan.files.first?.newText == "😀 🐶 😀 🐶")
    }

    @Test func aCancelledPlanStopsEarly() async throws {
        let query = SearchQuery(text: "x", options: SearchOptions())
        let expression = try query.regularExpression()
        let results = (1...3).compactMap { FolderSearch.search(SearchTarget(file: file("\($0).md"), unsavedText: "x"), for: expression) }

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ReplacePlan.make(results: results, query: query, replacement: "y") { _ in "x" }
        }

        #expect(try await task.value.files.isEmpty)
    }

    // MARK: Skipped files

    @Test func filesChangedSinceTheSearchAreSkipped() throws {
        let plan = try plan(["a.md": "x", "b.md": "x"], find: "x", replace: "y", current: ["a.md": "x edited", "b.md": "x"])

        #expect(plan.files.map(\.file.relativePath) == ["b.md"])
        #expect(plan.skipped.map(\.file.relativePath) == ["a.md"])
        #expect(plan.skipped.first?.reason == .changedSinceSearch)
    }

    @Test func unreadableFilesAreSkipped() throws {
        let plan = try plan(["a.md": "x"], find: "x", replace: "y", current: [:])

        #expect(plan.files.isEmpty)
        #expect(plan.skipped.first?.reason == .unreadable)
        #expect(ReplaceSkipReason.unreadable.description.isEmpty == false)
        #expect(ReplaceSkipReason.changedSinceSearch.description.contains("search again"))
    }
}
