//
//  AutosaveSchedulerTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

/// Autosave waits for typing to pause, and only writes files that exist on disk.
@MainActor
struct AutosaveSchedulerTests {
    private let root = URL(filePath: "/tmp/root", directoryHint: .isDirectory)

    @Test func savesOnceAfterTheDelay() async {
        let scheduler = AutosaveScheduler()
        scheduler.delay = .milliseconds(10)
        var saves = 0

        scheduler.schedule { saves += 1 }
        await scheduler.task?.value

        #expect(saves == 1)
    }

    @Test func anotherEditRestartsTheCountdown() async throws {
        let scheduler = AutosaveScheduler()
        scheduler.delay = .milliseconds(50)
        var saves: [String] = []

        scheduler.schedule { saves.append("first") }
        let first = try #require(scheduler.task)
        scheduler.schedule { saves.append("second") }
        await first.value
        await scheduler.task?.value

        #expect(saves == ["second"])
    }

    @Test func withoutADelayNothingIsScheduled() async {
        let scheduler = AutosaveScheduler()
        var saves = 0

        scheduler.schedule { saves += 1 }

        #expect(scheduler.task == nil)
        #expect(saves == 0)
    }

    @Test func turningAutosaveOffCancelsThePendingSave() async throws {
        let scheduler = AutosaveScheduler()
        scheduler.delay = .milliseconds(20)
        var saves = 0
        scheduler.schedule { saves += 1 }
        let pending = try #require(scheduler.task)

        scheduler.delay = nil
        scheduler.schedule { saves += 1 }
        await pending.value

        #expect(scheduler.task == nil)
        #expect(saves == 0)
    }

    @Test func savesOnlyEditedFilesThatExistOnDisk() {
        let clean = OpenDocument(url: root.appending(path: "clean.md"), text: "a")
        let edited = OpenDocument(url: root.appending(path: "edited.md"), text: "a").editing("b")
        let missing = OpenDocument(url: root.appending(path: "missing.md"), text: "a").editing("b")
        let new = OpenDocument.newFile(at: root.appending(path: "new.csv"), text: "x")
        let tabs = DocumentTabs.empty
            .opening(clean).opening(edited).opening(missing).opening(new)
            .marking(missing.id, missingOnDisk: true)

        #expect(AutosaveScheduler.documentsToSave(in: tabs) == [edited.id])
    }
}
