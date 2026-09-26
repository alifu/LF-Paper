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

    func makeCoordinator() -> MarkdownPreviewController {
        MarkdownPreviewController()
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.workspaceRoot = workspaceRoot
        context.coordinator.scheduleRender(markdown: markdown, documentURL: documentURL)
    }
}
