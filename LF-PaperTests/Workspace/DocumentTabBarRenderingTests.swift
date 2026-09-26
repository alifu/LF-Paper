//
//  DocumentTabBarRenderingTests.swift
//  LF-PaperTests
//

import AppKit
import SwiftUI
import Testing
@testable import LF_Paper

/// Renders the tab bar offscreen in dark and light mode and attaches the image for review.
@MainActor
final class DocumentTabBarRenderingTests {
    private static let size = NSSize(width: 520, height: 30)
    private let suiteName = "LFPaperTests.\(UUID().uuidString)"
    private let folder: TemporaryDirectory

    init() throws {
        folder = try TemporaryDirectory()
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    private func modelWithTabs() throws -> WorkspaceModel {
        try folder.makeFile("README.md", contents: "# Hi")
        try folder.makeFile("data.json", contents: "{}")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let model = WorkspaceModel(
            bookmarkStore: BookmarkStore(defaults: defaults),
            recentFolders: RecentFolders(defaults: defaults),
            watchesFileSystem: false
        )
        model.openFolder(folder.url)
        for item in model.children(of: folder.url) {
            model.selection = item.url
        }
        model.updateDocumentText("# Hi there") // README.md, the last opened, has unsaved changes
        return model
    }

    private func render(_ view: some View, appearance: NSAppearance.Name) throws -> NSBitmapImageRep {
        let hostingView = NSHostingView(rootView: view.frame(width: Self.size.width, height: Self.size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        let bitmap = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return bitmap
    }

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func tabsShowTheirNames(appearance: NSAppearance.Name) throws {
        let model = try modelWithTabs()
        #expect(model.tabs.count == 2)

        let empty = try render(DocumentTabBar(model: WorkspaceModel(watchesFileSystem: false)), appearance: appearance)
        let bitmap = try render(DocumentTabBar(model: model), appearance: appearance)
        Attachment.record(try #require(bitmap.representation(using: .png, properties: [:])), named: "tabs-\(appearance.rawValue).png")

        let isDark = appearance == .darkAqua
        let isText: (CGFloat) -> Bool = { isDark ? $0 > 0.6 : $0 < 0.4 }
        let emptyText = PixelCounter.count(in: empty, matching: isText)
        let text = PixelCounter.count(in: bitmap, matching: isText)
        #expect(text > emptyText + 15, "tab names should be visible (empty: \(emptyText), with tabs: \(text))")
    }
}
