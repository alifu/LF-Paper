//
//  GitRepository.swift
//  LF-Paper
//

import Foundation

/// Reads files from the last commit (HEAD) of a Git repository, for Compare with Last Commit.
///
/// The sandbox can't run the `git` tool, so this reads the repository directly: HEAD and branch
/// refs (loose or packed), commits, trees and blobs, loose or in packs (including deltas).
/// It only reads; it never changes the repository.
nonisolated struct GitRepository: Equatable, Sendable {
    /// Symbolic refs pointing at refs pointing at… are cut off at this depth.
    private static let maximumRefDepth = 5

    /// The `.git` folder.
    let gitDirectory: URL
    /// The folder with the checked-out files.
    let workTree: URL

    /// The repository containing `folder`, looking in its parent folders too.
    /// Folders the sandbox can't read count as not being in a repository.
    static func find(containing folder: URL) -> GitRepository? {
        var candidate = folder.standardizedFileURL
        while true {
            let dotGit = candidate.appending(path: ".git")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: dotGit.path(percentEncoded: false), isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    return GitRepository(gitDirectory: dotGit, workTree: candidate)
                }
                // A worktree or submodule: ".git" is a file saying "gitdir: <path>".
                if let linked = linkedGitDirectory(in: dotGit) {
                    return GitRepository(gitDirectory: linked, workTree: candidate)
                }
            }
            // Going up from "/" gives "/..", so stop by counting components instead.
            guard candidate.pathComponents.count > 1 else { return nil }
            candidate = candidate.deletingLastPathComponent().standardizedFileURL
        }
    }

    // MARK: Reading

    /// The commit HEAD points at.
    func headCommit() throws(GitError) -> GitObjectID {
        var reference = try text(at: "HEAD")
        for _ in 0..<Self.maximumRefDepth {
            guard reference.hasPrefix("ref: ") else {
                guard let id = GitObjectID(hex: reference) else { throw .corrupt("HEAD is damaged") }
                return id
            }
            let name = String(reference.dropFirst("ref: ".count))
            guard let target = try resolvedReference(name) else { throw .noCommits }
            reference = target
        }
        throw .corrupt("HEAD refers to itself")
    }

    /// The contents of a file (path components from the work tree) as it is in the last commit.
    func fileAtHead(_ path: [String]) throws(GitError) -> Data {
        let commit = try object(headCommit())
        guard commit.kind == .commit, let treeID = Self.treeID(ofCommit: commit.data) else { throw .corrupt("HEAD isn't a commit") }

        var current = treeID
        for (index, name) in path.enumerated() {
            let tree = try object(current)
            guard tree.kind == .tree, let entry = Self.entry(named: name, inTree: tree.data) else {
                throw .fileNotInCommit(path.joined(separator: "/"))
            }
            let isLast = index == path.count - 1
            guard entry.isFolder != isLast else { throw .fileNotInCommit(path.joined(separator: "/")) }
            current = entry.id
        }
        let blob = try object(current)
        guard blob.kind == .blob else { throw .fileNotInCommit(path.joined(separator: "/")) }
        return blob.data
    }

    /// Any object, loose or packed.
    func object(_ id: GitObjectID) throws(GitError) -> GitObject {
        if let loose = try looseObject(id) { return loose }
        for pack in try packs() {
            if let offset = pack.offset(of: id) {
                return try pack.object(at: offset) { (baseID: GitObjectID) throws(GitError) -> GitObject in
                    try object(baseID)
                }
            }
        }
        throw .missingObject(id.description)
    }

    // MARK: Objects

    private func looseObject(_ id: GitObjectID) throws(GitError) -> GitObject? {
        let hex = id.description
        let url = gitDirectory.appending(path: "objects/\(hex.prefix(2))/\(hex.dropFirst(2))")
        guard let compressed = try? Data(contentsOf: url) else { return nil }
        let raw = try Zlib.inflate(compressed)
        // "<type> <size>\0<contents>"
        guard let nul = raw.firstIndex(of: 0),
              let header = String(data: raw[raw.startIndex..<nul], encoding: .ascii),
              let space = header.firstIndex(of: " "),
              let kind = GitObject.Kind(name: String(header[..<space])),
              let size = Int(header[header.index(after: space)...]),
              raw.endIndex - raw.index(after: nul) == size
        else { throw .corrupt("object \(hex) is damaged") }
        return GitObject(kind: kind, data: Data(raw[raw.index(after: nul)...]))
    }

    private func packs() throws(GitError) -> [GitPack] {
        let folder = gitDirectory.appending(path: "objects/pack")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        var packs: [GitPack] = []
        for name in names.sorted() where name.hasSuffix(".idx") {
            packs.append(try GitPack(indexURL: folder.appending(path: name)))
        }
        return packs
    }

    // MARK: Commits and trees

    /// The first line of a commit is "tree <hex>".
    private static func treeID(ofCommit data: Data) -> GitObjectID? {
        guard let firstLine = String(decoding: data.prefix(64), as: UTF8.self).split(separator: "\n").first,
              firstLine.hasPrefix("tree ")
        else { return nil }
        return GitObjectID(hex: firstLine.dropFirst("tree ".count))
    }

    /// Tree entries are "<mode> <name>\0<20-byte id>", one after another. Folders have mode 40000.
    private static func entry(named name: String, inTree data: Data) -> (id: GitObjectID, isFolder: Bool)? {
        let wanted = Array(name.utf8)
        var position = data.startIndex
        while position < data.endIndex {
            guard let space = data[position...].firstIndex(of: UInt8(ascii: " ")),
                  let nul = data[space...].firstIndex(of: 0),
                  nul + 1 + GitObjectID.byteCount <= data.endIndex
            else { return nil }
            let isFolder = data[position..<space].elementsEqual("40000".utf8)
            let entryName = data[(space + 1)..<nul]
            let idBytes = data[(nul + 1)..<(nul + 1 + GitObjectID.byteCount)]
            if entryName.elementsEqual(wanted), let id = GitObjectID(bytes: idBytes) {
                return (id, isFolder)
            }
            position = nul + 1 + GitObjectID.byteCount
        }
        return nil
    }

    // MARK: Refs

    /// A ref's value from its file, or else from `packed-refs`. `nil` when the ref doesn't exist.
    private func resolvedReference(_ name: String) throws(GitError) -> String? {
        if let loose = try? text(at: name) { return loose }
        guard let packed = try? text(at: "packed-refs") else { return nil }
        for line in packed.split(separator: "\n") where !line.hasPrefix("#") && !line.hasPrefix("^") {
            let parts = line.split(separator: " ", maxSplits: 1)
            if parts.count == 2, parts[1] == name { return String(parts[0]) }
        }
        return nil
    }

    private func text(at path: String) throws(GitError) -> String {
        guard let data = try? Data(contentsOf: gitDirectory.appending(path: path)) else { throw .corrupt("\(path) is missing") }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func linkedGitDirectory(in dotGitFile: URL) -> URL? {
        guard let contents = try? String(contentsOf: dotGitFile, encoding: .utf8),
              let line = contents.split(separator: "\n").first, line.hasPrefix("gitdir: ")
        else { return nil }
        let path = line.dropFirst("gitdir: ".count).trimmingCharacters(in: .whitespaces)
        return path.hasPrefix("/")
            ? URL(filePath: path, directoryHint: .isDirectory)
            : dotGitFile.deletingLastPathComponent().appending(path: path, directoryHint: .isDirectory).standardizedFileURL
    }
}
