//
//  MarkdownPreviewView.swift
//  LF-Paper
//

import SwiftUI
import WebKit

/// SwiftUI host for the Markdown preview. The controller lives as long as the view.
struct MarkdownPreviewView: NSViewRepresentable {
    let markdown: String
    let documentURL: URL
    let workspaceRoot: URL?
    /// Where the editor scrolled; each target is applied once.
    var scrollTarget: ScrollSync.PreviewTarget?
    /// Where the reader scrolled the preview, as a source line.
    var onScroll: (Double) -> Void = { _ in }

    func makeCoordinator() -> MarkdownPreviewController {
        MarkdownPreviewController()
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let controller = context.coordinator
        controller.workspaceRoot = workspaceRoot
        controller.onScroll = onScroll
        controller.scheduleRender(markdown: markdown, documentURL: documentURL)
        if let scrollTarget, scrollTarget.id != controller.lastScrollTargetID {
            controller.lastScrollTargetID = scrollTarget.id
            controller.scroll(toLine: scrollTarget.line)
        }
    }
}
