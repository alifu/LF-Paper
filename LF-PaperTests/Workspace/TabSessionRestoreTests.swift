//
//  TabSessionRestoreTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

/// Turning open tabs into a session and back, without a model or the disk.
struct TabSessionRestoreTests {
    private let root = URL(filePath: "/tmp/root", directoryHint: .isDirectory)

    private func document(_ path: String, text: String = "") -> OpenDocument {
        OpenDocument(url: root.appending(path: path, directoryHint: .notDirectory), text: text)
    }

    // MARK: Make

    @Test func makeKeepsTabOrderActiveTabAndSelections() {
        let a = document("a.md")
        let c = document("docs/c.md")
        let tabs = DocumentTabs.empty.opening(a).opening(c).activating(a.id)

        let session = TabSession.make(from: tabs, root: root, selections: [c.id: NSRange(location: 3, length: 1)])

        #expect(session == TabSession(files: ["a.md", "docs/c.md"], activeFile: "a.md", selections: ["docs/c.md": NSRange(location: 3, length: 1)]))
    }

    @Test func makeLeavesOutFilesOutsideTheFolder() {
        let inside = document("a.md")
        let outside = OpenDocument(url: URL(filePath: "/tmp/elsewhere/b.md"), text: "")
        let tabs = DocumentTabs.empty.opening(inside).opening(outside)

        let session = TabSession.make(from: tabs, root: root, selections: [outside.id: NSRange(location: 0, length: 0)])

        #expect(session.files == ["a.md"])
        #expect(session.activeFile == nil)
        #expect(session.selections.isEmpty)
    }

    @Test func makeFromNoTabsIsEmpty() {
        let session = TabSession.make(from: .empty, root: root, selections: [:])

        #expect(session.files.isEmpty)
        #expect(session.activeFile == nil)
    }

    // MARK: Restore

    @Test func restoreReopensFilesInOrderWithTheActiveTab() throws {
        let session = TabSession(files: ["a.md", "docs/c.md"], activeFile: "a.md", selections: [:])

        let (tabs, _) = session.restore(in: root) { "text of \($0.lastPathComponent)" }

        #expect(tabs.documents.map(\.url.lastPathComponent) == ["a.md", "c.md"])
        #expect(tabs.documents.map(\.text) == ["text of a.md", "text of c.md"])
        #expect(tabs.active?.url.lastPathComponent == "a.md")
        #expect(tabs.documents.allSatisfy { !$0.isDirty })
    }

    @Test func restoreSkipsFilesThatAreGone() {
        let session = TabSession(files: ["a.md", "gone.md", "b.md"], activeFile: "gone.md", selections: ["gone.md": NSRange(location: 1, length: 0)])

        let (tabs, pending) = session.restore(in: root) { $0.lastPathComponent == "gone.md" ? nil : "" }

        #expect(tabs.documents.map(\.url.lastPathComponent) == ["a.md", "b.md"])
        #expect(tabs.active?.url.lastPathComponent == "b.md") // the last one opened
        #expect(pending.isEmpty)
    }

    @Test func restoreGivesEachTabItsPendingSelection() throws {
        let range = NSRange(location: 4, length: 2)
        let session = TabSession(files: ["a.md", "b.md"], activeFile: nil, selections: ["b.md": range])

        let (tabs, pending) = session.restore(in: root) { _ in "" }

        let b = try #require(tabs.documents.last)
        #expect(pending == [b.id: range])
    }

    @Test func makeAndRestoreRoundTrip() {
        let a = document("a.md", text: "A")
        let c = document("docs/c.md", text: "C")
        let tabs = DocumentTabs.empty.opening(a).opening(c)
        let session = TabSession.make(from: tabs, root: root, selections: [a.id: NSRange(location: 1, length: 0)])

        let (restored, pending) = session.restore(in: root) { url in [a.url, c.url].contains(url) ? (url == a.url ? "A" : "C") : nil }

        #expect(restored.documents.map(\.url) == [a.url, c.url])
        #expect(restored.active?.url == c.url)
        #expect(Array(pending.values) == [NSRange(location: 1, length: 0)])
        #expect(TabSession.make(from: restored, root: root, selections: pending) == session)
    }
}

/// Which selection each tab remembers: what the editor reported, or what's still waiting to be put back.
struct TabSelectionMemoryTests {
    private let first = UUID()
    private let second = UUID()

    @Test func notingASelectionReplacesThePendingOne() {
        let memory = TabSelectionMemory(pending: [first: NSRange(location: 9, length: 0)])

        let noted = memory.noting(NSRange(location: 2, length: 1), in: first)

        #expect(noted.selections == [first: NSRange(location: 2, length: 1)])
        #expect(noted.takingPending(for: first).range == nil)
        #expect(memory.selections == [first: NSRange(location: 9, length: 0)])
    }

    @Test func selectionsCombineNotedAndPending() {
        let memory = TabSelectionMemory(pending: [second: NSRange(location: 5, length: 0)])
            .noting(NSRange(location: 1, length: 0), in: first)

        #expect(memory.selections == [first: NSRange(location: 1, length: 0), second: NSRange(location: 5, length: 0)])
    }

    @Test func takingThePendingSelectionRemovesIt() {
        let memory = TabSelectionMemory(pending: [first: NSRange(location: 3, length: 0)])

        let (range, rest) = memory.takingPending(for: first)

        #expect(range == NSRange(location: 3, length: 0))
        #expect(rest.takingPending(for: first).range == nil)
        #expect(rest.selections.isEmpty)
        #expect(memory.takingPending(for: second).range == nil)
    }

    @Test func emptyRemembersNothing() {
        #expect(TabSelectionMemory.empty.selections.isEmpty)
    }
}
