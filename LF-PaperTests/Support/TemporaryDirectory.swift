//
//  TemporaryDirectory.swift
//  LF-PaperTests
//

import Foundation

/// A uniquely named scratch folder that is deleted when the instance goes away.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "LFPaperTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        // Best-effort cleanup of test scratch space.
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func makeFile(_ relativePath: String, contents: String = "") throws -> URL {
        let fileURL = url.appending(path: relativePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: fileURL)
        return fileURL
    }

    @discardableResult
    func makeFolder(_ relativePath: String) throws -> URL {
        let folderURL = url.appending(path: relativePath, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appending(path: relativePath).path(percentEncoded: false))
    }

    func contents(of relativePath: String) throws -> String {
        try String(contentsOf: url.appending(path: relativePath), encoding: .utf8)
    }
}
