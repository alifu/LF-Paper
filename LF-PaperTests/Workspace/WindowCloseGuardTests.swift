//
//  WindowCloseGuardTests.swift
//  LF-PaperTests
//

import AppKit
import Testing
@testable import LF_Paper

/// Closing a window with unsaved changes asks first (or saves, per Settings), and every other
/// window-delegate message still reaches SwiftUI's own delegate.
@MainActor
final class WindowCloseGuardTests {
    private let workspace: TestWorkspace
    private let window: NSWindow
    private let original = RecordingDelegate()
    private var behavior = UnsavedChangesOnClose.ask
    private var askedAbout: [String] = []
    private var answer: ((WorkspaceModel.UnsavedChangesDecision) -> Void)?
    private var closeCount = 0
    private lazy var closeGuard = WindowCloseGuard(
        model: workspace.model,
        behavior: { [unowned self] in behavior },
        ask: { [unowned self] _, documents, answer in
            askedAbout = documents.map(\.url.lastPathComponent)
            self.answer = answer
        }
    )

    init() throws {
        workspace = try TestWorkspace(files: ["a.md": "A"])
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.delegate = original
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeCount += 1 }
        }
    }

    private func edit() throws {
        try workspace.open("a.md")
        workspace.model.updateDocumentText("A edited")
    }

    private func shouldClose() -> Bool {
        closeGuard.attach(to: window)
        return window.delegate?.windowShouldClose?(window) ?? true
    }

    @Test func closesWithoutAskingWhenNothingIsUnsaved() {
        #expect(shouldClose())
        #expect(askedAbout.isEmpty)
    }

    @Test func asksAboutTheEditedFilesAndWaitsForTheAnswer() throws {
        try edit()

        #expect(!shouldClose())
        #expect(askedAbout == ["a.md"])
        #expect(closeCount == 0)
    }

    @Test func saveWritesTheFilesAndCloses() throws {
        try edit()
        _ = shouldClose()

        answer?(.save)

        #expect(try workspace.folder.contents(of: "a.md") == "A edited")
        #expect(closeCount == 1)
    }

    @Test func dontSaveRevertsAndCloses() throws {
        try edit()
        _ = shouldClose()

        answer?(.discard)

        #expect(try workspace.folder.contents(of: "a.md") == "A")
        #expect(!workspace.model.hasUnsavedChanges)
        #expect(closeCount == 1)
    }

    @Test func cancelKeepsTheWindowAndTheEdits() throws {
        try edit()
        _ = shouldClose()

        answer?(.cancel)

        #expect(workspace.model.hasUnsavedChanges)
        #expect(closeCount == 0)
    }

    @Test func savingAutomaticallyClosesWithoutAsking() throws {
        behavior = .saveAutomatically
        try edit()

        #expect(shouldClose())
        #expect(askedAbout.isEmpty)
        #expect(try workspace.folder.contents(of: "a.md") == "A edited")
    }

    @Test func aFailedAutomaticSaveKeepsTheWindowOpen() throws {
        behavior = .saveAutomatically
        try edit()
        try FileManager.default.removeItem(at: workspace.folder.url)

        #expect(!shouldClose())
        #expect(workspace.model.presentedError != nil)
    }

    @Test func respectsTheOriginalDelegatesAnswer() {
        original.allowsClose = false

        #expect(!shouldClose())
    }

    @Test func forwardsEveryOtherMessageToTheOriginalDelegate() throws {
        closeGuard.attach(to: window)
        let delegate = try #require(window.delegate as? NSObject)

        #expect(delegate.responds(to: #selector(NSWindowDelegate.windowDidResize(_:))))
        #expect(!delegate.responds(to: #selector(NSWindowDelegate.windowDidMove(_:))))
        window.delegate?.windowDidResize?(Notification(name: NSWindow.didResizeNotification, object: window))

        #expect(original.resizeCount == 1)
    }

    @Test func attachingTwiceKeepsTheOriginalDelegate() {
        closeGuard.attach(to: window)
        closeGuard.attach(to: window)

        #expect(closeGuard.originalDelegate === original)
    }
}

/// Stands in for SwiftUI's window delegate.
private final class RecordingDelegate: NSObject, NSWindowDelegate {
    var allowsClose = true
    var resizeCount = 0

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        allowsClose
    }

    func windowDidResize(_ notification: Notification) {
        resizeCount += 1
    }
}
