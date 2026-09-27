//
//  FolderTreeTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

/// The sidebar's loaded folders, as a value: loading, expanding, reloading and lookups.
struct FolderTreeTests {
    private let root = URL(filePath: "/tmp/root", directoryHint: .isDirectory)
    private var docs: URL { root.appending(path: "docs", directoryHint: .isDirectory) }
    private var guide: URL { docs.appending(path: "guide", directoryHint: .isDirectory) }

    private func file(_ url: URL) -> FileItem { FileItem(url: url, kind: .markdown) }
    private func folder(_ url: URL) -> FileItem { FileItem(url: url, kind: .folder) }

    private var readme: FileItem { file(root.appending(path: "README.md")) }
    private var intro: FileItem { file(docs.appending(path: "intro.md")) }

    /// A fake folder listing: `contents` by folder, anything else is missing.
    private func lister(_ contents: [URL: [FileItem]], failing: [URL: AppError] = [:]) -> FolderTree.Lister {
        { url throws(AppError) in
            if let error = failing[url] { throw error }
            guard let items = contents[url] else { throw .fileNotFound(url) }
            return items
        }
    }

    @Test func openingListsOnlyTheRoot() {
        let tree = FolderTree.opening(root, items: [readme, folder(docs)])

        #expect(tree.root == root)
        #expect(tree.children(of: root) == [readme, folder(docs)])
        #expect(tree.isLoaded(root))
        #expect(!tree.isLoaded(docs))
        #expect(tree.children(of: docs).isEmpty)
        #expect(tree.expandedFolders.isEmpty)
    }

    @Test func emptyTreeHasNoRootOrItems() {
        #expect(FolderTree.empty.root == nil)
        #expect(FolderTree.empty.item(at: root) == nil)
        #expect(FolderTree.empty.targetFolder(for: nil) == nil)
    }

    @Test func loadingAFolderAddsItsItemsWithoutChangingTheOriginal() throws {
        let tree = FolderTree.opening(root, items: [folder(docs)])

        let loaded = try tree.loading(docs, using: lister([docs: [intro]]))

        #expect(loaded.children(of: docs) == [intro])
        #expect(!tree.isLoaded(docs))
    }

    @Test func loadingAMissingFolderThrows() {
        let tree = FolderTree.opening(root, items: [])

        #expect(throws: AppError.fileNotFound(docs)) {
            try tree.loading(docs, using: lister([:]))
        }
    }

    @Test func expandingAndCollapsing() {
        let tree = FolderTree.opening(root, items: [folder(docs)])

        let expanded = tree.expanding(docs)
        #expect(expanded.expandedFolders == [docs])
        #expect(expanded.collapsing(docs).expandedFolders.isEmpty)
        #expect(tree.expandedFolders.isEmpty)
    }

    @Test func itemLookupIgnoresSpellingDifferences() throws {
        let tree = try FolderTree.opening(root, items: [folder(docs)])
            .loading(docs, using: lister([docs: [intro]]))

        #expect(tree.item(at: URL(filePath: "/tmp/root/docs/")) == folder(docs))
        #expect(tree.item(at: URL(filePath: "/tmp/root/docs/./intro.md")) == intro)
        #expect(tree.item(at: root.appending(path: "nope.md")) == nil)
    }

    @Test func reloadingRereadsTheRootAndExpandedFoldersOnly() throws {
        let tree = try FolderTree.opening(root, items: [folder(docs)])
            .loading(docs, using: lister([docs: []]))
            .expanding(docs)
            .loading(guide, using: lister([guide: []])) // loaded but collapsed: dropped

        let (reloaded, errors) = tree.reloading(using: lister([root: [folder(docs), readme], docs: [intro]]))

        #expect(errors.isEmpty)
        #expect(reloaded.children(of: root) == [folder(docs), readme])
        #expect(reloaded.children(of: docs) == [intro])
        #expect(!reloaded.isLoaded(guide))
        #expect(reloaded.expandedFolders == [docs])
    }

    @Test func reloadingDropsFoldersThatDisappeared() throws {
        let tree = try FolderTree.opening(root, items: [folder(docs)])
            .loading(docs, using: lister([docs: []]))
            .expanding(docs)

        let (reloaded, errors) = tree.reloading(using: lister([root: []]))

        #expect(errors.isEmpty) // gone on disk is expected, not an error
        #expect(!reloaded.isLoaded(docs))
        #expect(reloaded.expandedFolders.isEmpty)
    }

    @Test func reloadingReportsOtherErrors() throws {
        let tree = try FolderTree.opening(root, items: [folder(docs)])
            .loading(docs, using: lister([docs: []]))
            .expanding(docs)

        let (reloaded, errors) = tree.reloading(using: lister([root: [folder(docs)]], failing: [docs: .accessDenied(docs)]))

        #expect(errors == [.accessDenied(docs)])
        #expect(!reloaded.isLoaded(docs))
        #expect(reloaded.children(of: root) == [folder(docs)])
    }

    @Test func reloadingWithoutARootChangesNothing() {
        let (reloaded, errors) = FolderTree.empty.reloading(using: lister([:]))

        #expect(reloaded == .empty)
        #expect(errors.isEmpty)
    }

    @Test func targetFolderIsTheFolderItselfOrTheFilesParent() throws {
        let tree = try FolderTree.opening(root, items: [folder(docs), readme])
            .loading(docs, using: lister([docs: [intro]]))

        #expect(tree.targetFolder(for: nil) == root)
        #expect(tree.targetFolder(for: folder(docs)) == docs)
        #expect(tree.targetFolder(for: intro) == docs)
        #expect(tree.targetFolder(for: readme) == root)
        // Not loaded: falls back to the path's parent.
        #expect(tree.targetFolder(for: file(guide.appending(path: "x.md")))?.lastPathComponent == "guide")
    }
}
