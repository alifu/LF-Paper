//
//  ScratchpadRenderingTests.swift
//  LF-PaperTests
//

import AppKit
import SwiftUI
import Testing
@testable import LF_Paper

/// Renders the scratchpad's tab and bar offscreen in dark and light mode and attaches the images for review.
@MainActor
final class ScratchpadRenderingTests {
    private static let tabBarSize = NSSize(width: 520, height: 30)
    private static let barSize = NSSize(width: 520, height: 32)
    private let suiteName = "LFPaperTests.\(UUID().uuidString)"
    private let folder: TemporaryDirectory

    init() throws {
        folder = try TemporaryDirectory()
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    private func makeModel() throws -> WorkspaceModel {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return WorkspaceModel(
            bookmarkStore: BookmarkStore(defaults: defaults),
            recentFolders: RecentFolders(defaults: defaults),
            watchesFileSystem: false
        )
    }

    private func render(_ view: some View, size: NSSize, appearance: NSAppearance.Name) throws -> NSBitmapImageRep {
        let hostingView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        let bitmap = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return bitmap
    }

    /// Looser than the tab-name check elsewhere: the counts are small, secondary-gray text,
    /// whose antialiased pixels rarely get darker than 0.4 on a light background.
    private func textPixels(in bitmap: NSBitmapImageRep, appearance: NSAppearance.Name) -> Int {
        let isDark = appearance == .darkAqua
        return PixelCounter.count(in: bitmap) { isDark ? $0 > 0.5 : $0 < 0.6 }
    }

    private func attach(_ bitmap: NSBitmapImageRep, named name: String) throws {
        Attachment.record(try #require(bitmap.representation(using: .png, properties: [:])), named: name)
    }

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func scratchTabShowsWithoutAnyFiles(appearance: NSAppearance.Name) throws {
        let model = try makeModel()

        let bitmap = try render(DocumentTabBar(model: model), size: Self.tabBarSize, appearance: appearance)
        let blank = try render(Color(nsColor: .windowBackgroundColor), size: Self.tabBarSize, appearance: appearance)
        try attach(bitmap, named: "scratch-tab-only-\(appearance.rawValue).png")

        let text = textPixels(in: bitmap, appearance: appearance)
        let blankText = textPixels(in: blank, appearance: appearance)
        #expect(text > blankText + 15, "the Scratch tab should be visible (blank: \(blankText), tab bar: \(text))")
    }

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func scratchTabSitsBeforeFileTabs(appearance: NSAppearance.Name) throws {
        try folder.makeFile("README.md", contents: "# Hi")
        try folder.makeFile("data.json", contents: "{}")
        let model = try makeModel()
        model.openFolder(folder.url)
        for item in model.children(of: folder.url) {
            model.selection = item.url
        }
        model.showScratchpad()
        let scratchOnly = try render(DocumentTabBar(model: try makeModel()), size: Self.tabBarSize, appearance: appearance)

        let bitmap = try render(DocumentTabBar(model: model), size: Self.tabBarSize, appearance: appearance)
        try attach(bitmap, named: "scratch-tab-with-files-\(appearance.rawValue).png")

        let text = textPixels(in: bitmap, appearance: appearance)
        let scratchText = textPixels(in: scratchOnly, appearance: appearance)
        #expect(text > scratchText + 15, "file tabs should follow the Scratch tab (scratch only: \(scratchText), with files: \(text))")
    }

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func barShowsCountsAndButtons(appearance: NSAppearance.Name) throws {
        let model = try makeModel()
        model.updateScratchpadText("Summarize this file\nin three bullet points.")

        let bitmap = try render(ScratchpadBar(model: model), size: Self.barSize, appearance: appearance)
        let blank = try render(Color(nsColor: .windowBackgroundColor), size: Self.barSize, appearance: appearance)
        try attach(bitmap, named: "scratchpad-bar-\(appearance.rawValue).png")

        let text = textPixels(in: bitmap, appearance: appearance)
        let blankText = textPixels(in: blank, appearance: appearance)
        #expect(text > blankText + 40, "counts and buttons should be visible (blank: \(blankText), bar: \(text))")
    }

    @Test func countsDescribeTheText() {
        #expect(ScratchpadBar.countsDescription(ScratchpadStats(text: "")) == "0 characters · 0 words · 0 lines")
        #expect(ScratchpadBar.countsDescription(ScratchpadStats(text: "a")) == "1 character · 1 word · 1 line")
        #expect(ScratchpadBar.countsDescription(ScratchpadStats(text: "ab cd\nef")) == "8 characters · 3 words · 2 lines")
    }
}
