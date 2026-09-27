//
//  PreviewScrollSyncTests.swift
//  LF-PaperTests
//

import AppKit
import Testing
import WebKit
@testable import LF_Paper

/// The preview scrolls to the editor's line, and reports where the reader scrolled it.
@MainActor
final class PreviewScrollSyncTests {
    private static let size = NSSize(width: 500, height: 300)
    /// Paragraph n is on source line 2n - 1 (a blank line between each).
    private static let markdown = (1...80).map { "Paragraph \($0) with enough words to be a real line of text." }.joined(separator: "\n\n")

    private let controller = MarkdownPreviewController()
    private let window: NSWindow
    private let folder: TemporaryDirectory
    private var reportedLines: [Double] = []

    init() throws {
        folder = try TemporaryDirectory()
        window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = controller.webView
        controller.onScroll = { [unowned self] in reportedLines.append($0) }
    }

    private func load() async {
        await controller.show(bodyHTML: MarkdownRenderer.html(from: Self.markdown, includesSourcePositions: true), documentFolder: folder.url)
    }

    private func evaluate(_ script: String) async throws -> Any? {
        try await controller.webView.callAsyncJavaScript(script, contentWorld: .defaultClient)
    }

    /// How far the block starting on `line` is from the top of the visible page.
    private func distanceFromTop(ofLine line: Int) async throws -> Double {
        let value = try await evaluate("""
            const el = [...document.querySelectorAll('[data-sourcepos]')].find(e => e.getAttribute('data-sourcepos').startsWith('\(line):'));
            return el.getBoundingClientRect().top;
            """)
        return try #require(value as? Double)
    }

    @Test func scrollsTheBlockOnTheEditorsLineToTheTop() async throws {
        await load()

        controller.scroll(toLine: 41)
        await controller.scrollTask?.value

        #expect(abs(try await distanceFromTop(ofLine: 41)) < 2)
    }

    @Test func aLineInsideABlockScrollsPartWay() async throws {
        await load()

        controller.scroll(toLine: 42) // the blank line between paragraphs 21 and 22
        await controller.scrollTask?.value

        let top = try await distanceFromTop(ofLine: 41)
        #expect(top < -2 && top > -60, "paragraph 21 should be partly scrolled past (top \(top))")
    }

    @Test func reportsTheLineWhenTheReaderScrolls() async throws {
        await load()
        let target = try #require(try await evaluate("""
            const el = [...document.querySelectorAll('[data-sourcepos]')].find(e => e.getAttribute('data-sourcepos').startsWith('61:'));
            return el.getBoundingClientRect().top + window.scrollY;
            """) as? Double)

        controller.previewDidScroll(toOffset: target) // what the page's scroll listener sends
        await controller.scrollReportTask?.value

        let line = try #require(reportedLines.last)
        #expect(abs(line - 61) < 0.5, "reported \(line)")
    }

    @Test func itsOwnScrollingIsNotReportedBack() async throws {
        await load()

        controller.scroll(toLine: 41)
        await controller.scrollTask?.value
        let offset = try #require(try await evaluate("return window.scrollY") as? Double)
        controller.previewDidScroll(toOffset: offset) // the scroll event that follows
        await controller.scrollReportTask?.value

        #expect(reportedLines.isEmpty)
    }

    @Test func thePagesScrollListenerLivesOnlyInTheAppsWorld() async throws {
        await load()

        let appWorld = try await evaluate("return typeof window.webkit?.messageHandlers?.previewScroll") as? String
        // With page JavaScript off the page world may not run scripts at all; either way it can't reach the handler.
        let pageWorld = try? await controller.webView.callAsyncJavaScript(
            "return typeof window.webkit?.messageHandlers?.previewScroll",
            contentWorld: .page
        ) as? String

        #expect(appWorld == "object")
        #expect(pageWorld != "object")
    }
}
