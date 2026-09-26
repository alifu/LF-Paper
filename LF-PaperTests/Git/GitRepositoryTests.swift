//
//  GitRepositoryTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

/// Reading files from the last commit, on repositories written by the real git command.
struct GitRepositoryTests {
    private let folder: TemporaryDirectory

    init() throws {
        folder = try TemporaryDirectory()
    }

    private func repository(_ files: [String: String]) throws -> GitRepository {
        try GitFixtures.install(files, in: folder.url)
        return try #require(GitRepository.find(containing: folder.url))
    }

    private func text(_ path: String, in repository: GitRepository) throws -> String {
        String(decoding: try repository.fileAtHead(path.split(separator: "/").map(String.init)), as: UTF8.self)
    }

    @Test(arguments: [GitFixtures.looseRepository, GitFixtures.packedRepository])
    func readsEveryFileOfTheLastCommit(files: [String: String]) throws {
        let repository = try repository(files)

        #expect(try repository.headCommit().description == GitFixtures.headCommitID)
        #expect(try text("notes.md", in: repository) == GitFixtures.notesAtHead)
        #expect(try text("docs/config.json", in: repository) == GitFixtures.configAtHead)
        #expect(try text("new.md", in: repository) == GitFixtures.newFileAtHead)
    }

    @Test func resolvesDeltasInPacks() throws {
        let repository = try repository(GitFixtures.packedRepository)

        let delta = try repository.object(#require(GitObjectID(hex: GitFixtures.notesAtHeadObjectID)))
        let base = try repository.object(#require(GitObjectID(hex: GitFixtures.notesInFirstCommitObjectID)))

        #expect(delta.kind == .blob)
        #expect(String(decoding: delta.data, as: UTF8.self) == GitFixtures.notesAtHead)
        #expect(String(decoding: base.data, as: UTF8.self) == GitFixtures.notesInFirstCommit)
    }

    @Test func isFoundFromAFolderInsideTheRepository() throws {
        try GitFixtures.install(GitFixtures.looseRepository, in: folder.url)
        let docs = try folder.makeFolder("docs")

        let repository = try #require(GitRepository.find(containing: docs))

        #expect(repository.workTree.standardizedFileURL == folder.url.standardizedFileURL)
    }

    @Test func aFolderOutsideAnyRepositoryHasNone() {
        #expect(GitRepository.find(containing: folder.url) == nil)
    }

    @Test func followsADetachedHead() throws {
        let repository = try repository(GitFixtures.looseRepository)
        try Data((GitFixtures.headCommitID + "\n").utf8).write(to: folder.url.appending(path: ".git/HEAD"))

        #expect(try repository.headCommit().description == GitFixtures.headCommitID)
    }

    @Test func aFileThatIsNotInTheCommitIsReported() throws {
        let repository = try repository(GitFixtures.packedRepository)

        #expect(throws: GitError.fileNotInCommit("untracked.md")) {
            _ = try repository.fileAtHead(["untracked.md"])
        }
        #expect(throws: GitError.fileNotInCommit("docs/missing.json")) {
            _ = try repository.fileAtHead(["docs", "missing.json"])
        }
        #expect(throws: GitError.fileNotInCommit("docs")) {
            _ = try repository.fileAtHead(["docs"]) // a folder, not a file
        }
    }

    @Test func aRepositoryWithoutCommitsHasNoHead() throws {
        let repository = try repository(GitFixtures.looseRepository)
        try FileManager.default.removeItem(at: folder.url.appending(path: ".git/refs/heads/main"))

        #expect(throws: GitError.noCommits) {
            _ = try repository.headCommit()
        }
    }

    @Test func aTruncatedPackIndexIsAnErrorNotACrash() throws {
        let repository = try repository(GitFixtures.packedRepository)
        let indexName = try #require(GitFixtures.packedRepository.keys.first { $0.hasSuffix(".idx") })
        let indexURL = folder.url.appending(path: ".git/" + indexName)
        let index = try Data(contentsOf: indexURL)
        try index.prefix(1_100).write(to: indexURL) // the fan-out table, but not all the names

        #expect(throws: GitError.self) {
            _ = try repository.fileAtHead(["notes.md"])
        }
    }

    @Test func aDamagedObjectIsAnErrorNotACrash() throws {
        let repository = try repository(GitFixtures.looseRepository)
        let objectFile = folder.url.appending(path: ".git/objects/31/e78bc86388d8950276b47cec522b706122630b")
        try Data([0x78, 0x01, 0xFF, 0x00]).write(to: objectFile)

        #expect(throws: GitError.self) {
            _ = try repository.fileAtHead(["notes.md"])
        }
    }
}

/// Compare with Last Commit from the workspace.
@MainActor
struct WorkspaceGitComparisonTests {
    private let workspace: TestWorkspace

    init() throws {
        workspace = try TestWorkspace(files: [
            "notes.md": GitFixtures.notesAtHead.replacingOccurrences(of: "Line 1:", with: "Line one:"),
            "untracked.md": "# Not committed\n",
        ])
        try GitFixtures.install(GitFixtures.packedRepository, in: workspace.folder.url)
    }

    @Test func comparesTheLastCommitWithTheCurrentText() async throws {
        try workspace.open("notes.md")
        workspace.model.updateDocumentText(workspace.model.document!.text + "Unsaved line.\n")

        let request = try await workspace.model.comparisonWithLastCommit()

        #expect(request.left.title == "notes.md — Last Commit (31e78bc)")
        #expect(request.left.text == GitFixtures.notesAtHead)
        #expect(request.right.title == "notes.md — Current")
        #expect(request.right.text.hasSuffix("Unsaved line.\n"))
        #expect(request.kind == .text)
    }

    @Test func knowsWhenTheFolderIsInARepository() throws {
        try workspace.open("notes.md")

        #expect(workspace.model.isInGitRepository)
    }

    @Test func aFileThatWasNeverCommittedIsAnError() async throws {
        try workspace.open("untracked.md")

        await #expect(throws: AppError.notInLastCommit("untracked.md")) {
            _ = try await workspace.model.comparisonWithLastCommit()
        }
    }
}
