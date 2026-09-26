//
//  FileWatcherTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

struct FileWatcherTests {
    private static let eventTimeout: Duration = .seconds(5)

    @Test func reportsFileCreatedInsideTheWatchedFolder() async throws {
        let folder = try TemporaryDirectory()
        let (events, continuation) = AsyncStream.makeStream(of: Void.self)
        let watcher = try #require(FileWatcher(url: folder.url) { continuation.yield() })

        try folder.makeFile("nested/new.md")

        let didReportChange = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in events { return true }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: Self.eventTimeout)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        #expect(didReportChange)
        withExtendedLifetime(watcher) {}
    }
}
