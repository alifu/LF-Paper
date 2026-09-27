//
//  WorkspaceModel+Replace.swift
//  LF-Paper
//

import Foundation

/// Replace All: a preview of every replacement in the search results, then writing it.
/// Open tabs are edited (and left unsaved, undoable in the tab); closed files are written to disk.
extension WorkspaceModel {
    private enum AppliedReplacement {
        case editedTab
        case written
        case skipped(ReplaceSkipReason)
    }

    /// Edit › Replace in Folder (⌥⇧⌘F): shows the search in the sidebar with the Replace field focused.
    func showFolderReplace() {
        sidebarMode = .search
        replace.show()
    }

    /// There are search results to replace, and no search or preview is running.
    var canReplaceAll: Bool {
        !search.results.isEmpty && !search.isSearching && search.searchedQuery != nil && !replace.isPreparing
    }

    /// Works out the preview for replacing every match of the last search with the Replace text.
    func prepareReplaceAll() {
        guard canReplaceAll, let query = search.searchedQuery else { return }
        let results = search.results
        let replacement = replace.replacement
        let openTexts = openTextsByURL()
        replace.prepare {
            await Self.plan(results: results, query: query, replacement: replacement, openTexts: openTexts)
        }
    }

    /// Applies the preview, except the files left out, then searches again to show what's left.
    func applyReplaceAll() {
        guard let plan = replace.plan else { return }
        var written: [FileReplacement] = []
        var skipped = plan.skipped
        var replacedFiles = 0
        var replacedMatches = 0
        for file in plan.files where replace.isIncluded(file.id) {
            switch apply(file) {
            case .editedTab:
                break
            case .written:
                written.append(file)
            case .skipped(let reason):
                skipped.append(SkippedFile(file: file.file, reason: reason))
                continue
            }
            replacedFiles += 1
            replacedMatches += file.changes.count
        }
        replace.didReplace(
            ReplaceOutcome(action: .replaced(count: replacedMatches), fileCount: replacedFiles, skipped: skipped),
            written: written
        )
        reloadAll()
        runFolderSearch()
    }

    /// Puts back the text of the files the last Replace All wrote, unless they changed since.
    /// Open tabs aren't touched: they undo with their own ⌘Z.
    func undoReplaceAll() {
        var restored = 0
        var skipped: [SkippedFile] = []
        for file in replace.takeUndoRecord() {
            let tab = openTabs.document(at: file.file.url)
            let current = tab.map { $0.isDirty ? nil : $0.text } ?? FolderSearch.readText(of: file.file.url)
            guard current == file.newText else {
                skipped.append(SkippedFile(file: file.file, reason: .changedSinceSearch))
                continue
            }
            do throws(AppError) {
                try fileService.write(file.originalText, to: file.file.url)
                restored += 1
            } catch {
                skipped.append(SkippedFile(file: file.file, reason: .writeFailed(error)))
            }
        }
        replace.didUndo(ReplaceOutcome(action: .undone, fileCount: restored, skipped: skipped))
        reloadAll() // unedited tabs follow the disk
        if search.searchedQuery != nil { runFolderSearch() }
    }

    // MARK: Private

    @concurrent
    private static func plan(
        results: [FileSearchResult],
        query: SearchQuery,
        replacement: String,
        openTexts: [URL: String]
    ) async -> Result<ReplacePlan, ReplaceError> {
        do throws(ReplaceError) {
            let plan = try ReplacePlan.make(results: results, query: query, replacement: replacement) { file in
                openTexts[file.url.standardizedFileURL] ?? FolderSearch.readText(of: file.url)
            }
            return .success(plan)
        } catch {
            return .failure(error)
        }
    }

    /// Replaces in the file's tab if it's open, or else on disk, if its text is still the one planned from.
    private func apply(_ replacement: FileReplacement) -> AppliedReplacement {
        let url = replacement.file.url
        if let document = openTabs.document(at: url) {
            guard document.text == replacement.originalText else { return .skipped(.changedSinceSearch) }
            updateText(ofTab: document.id, to: replacement.newText)
            return .editedTab
        }
        guard let diskText = FolderSearch.readText(of: url) else { return .skipped(.unreadable) }
        guard diskText == replacement.originalText else { return .skipped(.changedSinceSearch) }
        do throws(AppError) {
            try fileService.write(replacement.newText, to: url)
            return .written
        } catch {
            return .skipped(.writeFailed(error))
        }
    }
}
