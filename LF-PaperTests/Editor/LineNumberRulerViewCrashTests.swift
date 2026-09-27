//
//  LineNumberRulerViewCrashTests.swift
//  LF-PaperTests
//

import AppKit
import SwiftUI
import Testing
@testable import LF_Paper

@MainActor
struct LineNumberRulerViewCrashTests {
    /// Reproduces a crash: switching from a short scratchpad to a 1000+ line file and back
    /// crosses the ruler's digit-width threshold twice, which used to reenter text layout mid-edit.
    @Test func crossingTheDigitWidthThresholdTwiceDoesNotCrash() async throws {
        let folder = try TemporaryDirectory()
        let bigFile = (1...1500).map { "line \($0)" }.joined(separator: "\n")
        try folder.makeFile("big.json", contents: bigFile)
        let suiteName = "LFPaperTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let model = WorkspaceModel(
            bookmarkStore: BookmarkStore(defaults: defaults),
            recentFolders: RecentFolders(defaults: defaults),
            watchesFileSystem: false
        )
        model.openFolder(folder.url)

        let hostingView = NSHostingView(rootView: EditorPane(model: model).frame(width: 600, height: 400))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hostingView

        func redraw() {
            hostingView.layoutSubtreeIfNeeded()
            if let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) {
                hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
            }
        }
        func findTextView(in view: NSView) -> NSTextView? {
            if let t = view as? NSTextView { return t }
            return view.subviews.lazy.compactMap(findTextView(in:)).first
        }

        model.showScratchpad()
        redraw()
        let textView = try #require(findTextView(in: hostingView))
        window.makeFirstResponder(textView)
        textView.insertText("hi\nthere", replacementRange: NSRange(location: 0, length: 0))
        redraw()

        model.selection = try #require(model.children(of: folder.url).first).url
        redraw()

        model.toggleScratchpad()
        redraw() // this used to crash
        await Task.yield() // let the deferred ruler thickness update run
        redraw()

        #expect(model.scratchpadText == "hi\nthere")
    }
}
