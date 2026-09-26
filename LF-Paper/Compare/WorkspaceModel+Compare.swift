//
//  WorkspaceModel+Compare.swift
//  LF-Paper
//

import Foundation

/// Comparisons of the active file with other versions of itself.
extension WorkspaceModel {
    /// "What did I change?": the saved text against the unsaved edits, or `nil` when there are none.
    func comparisonWithSavedVersion() -> ComparisonRequest? {
        guard let document, activeTabHasUnsavedChanges else { return nil }
        let name = document.url.lastPathComponent
        return ComparisonRequest(
            left: CompareModel.Side(title: "\(name) — Saved", text: document.savedText),
            right: CompareModel.Side(title: "\(name) — Edited", text: document.text),
            kind: CompareContentKind(fileKind: FileKind(fileExtension: document.url.pathExtension))
        )
    }
}

/// Compare with Last Commit: the file as committed at HEAD against its current text.
extension WorkspaceModel {
    /// The Git repository the folder is in, if any (looked up each time, so `git init` is noticed).
    var gitRepository: GitRepository? {
        rootURL.flatMap(GitRepository.find(containing:))
    }

    var isInGitRepository: Bool { gitRepository != nil }

    /// Reads the committed version off the main thread, since packs can be large.
    func comparisonWithLastCommit() async throws(AppError) -> ComparisonRequest {
        guard let document, let repository = gitRepository else { throw .notInRepository }
        let name = document.url.lastPathComponent
        guard let path = document.url.components(below: repository.workTree) else { throw .notInLastCommit(name) }

        let committed: (commit: GitObjectID, data: Data)
        do {
            committed = try await Self.readCommitted(path, in: repository)
        } catch .fileNotInCommit, .noCommits {
            throw .notInLastCommit(name)
        } catch {
            throw .gitReadFailed(name)
        }
        return ComparisonRequest(
            left: CompareModel.Side(title: "\(name) — Last Commit (\(committed.commit.shortDescription))", text: String(decoding: committed.data, as: UTF8.self)),
            right: CompareModel.Side(title: "\(name) — Current", text: document.text),
            kind: CompareContentKind(fileKind: FileKind(fileExtension: document.url.pathExtension))
        )
    }

    @concurrent
    private static func readCommitted(_ path: [String], in repository: GitRepository) async throws(GitError) -> (commit: GitObjectID, data: Data) {
        (try repository.headCommit(), try repository.fileAtHead(path))
    }
}
