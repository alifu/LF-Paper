//
//  MarkdownPreviewController.swift
//  LF-Paper
//

import AppKit
import os
import WebKit

/// Owns the preview's `WKWebView`. It loads the page once per folder, then swaps in new HTML
/// so the scroll position survives edits. Page JavaScript is off; links open in the browser.
final class MarkdownPreviewController: NSObject {
    private struct RenderRequest: Equatable {
        let markdown: String
        let documentURL: URL
    }

    /// Pause after typing before re-rendering, so fast typing doesn't queue up renders.
    private static let renderDelay: Duration = .milliseconds(150)
    private static let logger = Logger(subsystem: "AppWork.LF-Paper", category: "Preview")

    let webView: WKWebView
    private let assetHandler: PreviewAssetSchemeHandler
    private var pageURL: URL?
    private var isPageLoaded = false
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []
    private var lastRequest: RenderRequest?
    private var renderTask: Task<Void, Never>?

    override init() {
        let assetHandler = PreviewAssetSchemeHandler()
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.setURLSchemeHandler(assetHandler, forURLScheme: PreviewAssets.scheme)
        self.assetHandler = assetHandler
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.underPageBackgroundColor = .textBackgroundColor
    }

    /// Images are only served from inside this folder.
    var workspaceRoot: URL? {
        get { assetHandler.root }
        set { assetHandler.root = newValue }
    }

    /// Renders `markdown` in the background and shows it. Edits to the same document wait
    /// briefly first; switching documents renders right away.
    func scheduleRender(markdown: String, documentURL: URL) {
        let request = RenderRequest(markdown: markdown, documentURL: documentURL)
        guard request != lastRequest else { return }
        let isNewDocument = documentURL != lastRequest?.documentURL
        lastRequest = request

        renderTask?.cancel()
        renderTask = Task {
            if !isNewDocument {
                try? await Task.sleep(for: Self.renderDelay) // cancelled sleeps end early; checked below
            }
            guard !Task.isCancelled else { return }
            let bodyHTML = await MarkdownRenderer.renderHTML(markdown)
            guard !Task.isCancelled else { return }
            await show(
                bodyHTML: bodyHTML,
                documentFolder: documentURL.deletingLastPathComponent(),
                scrollsToTop: isNewDocument
            )
        }
    }

    /// Shows rendered HTML. Reuses the loaded page when the folder is unchanged.
    func show(bodyHTML: String, documentFolder: URL, scrollsToTop: Bool = false) async {
        let url = PreviewAssets.baseURL(for: documentFolder)
        if url == pageURL, isPageLoaded {
            await replaceContent(with: bodyHTML, scrollsToTop: scrollsToTop)
            return
        }
        pageURL = url
        isPageLoaded = false
        webView.loadHTMLString(PreviewPage.html(body: bodyHTML), baseURL: url)
        await withCheckedContinuation { loadWaiters.append($0) }
    }

    private func replaceContent(with bodyHTML: String, scrollsToTop: Bool) async {
        let script = """
            document.getElementById('content').innerHTML = html;
            if (scrollsToTop) { window.scrollTo(0, 0); }
            """
        do {
            _ = try await webView.callAsyncJavaScript(
                script,
                arguments: ["html": bodyHTML, "scrollsToTop": scrollsToTop],
                contentWorld: .defaultClient
            )
        } catch {
            Self.logger.error("Could not update the preview: \(error.localizedDescription)")
        }
    }

    private func finishLoading(succeeded: Bool) {
        isPageLoaded = succeeded
        let waiters = loadWaiters
        loadWaiters = []
        waiters.forEach { $0.resume() }
    }
}

extension MarkdownPreviewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        let decision = PreviewNavigationPolicy.decide(
            url: navigationAction.request.url,
            isLinkClick: navigationAction.navigationType == .linkActivated,
            pageURL: pageURL
        )
        switch decision {
        case .allow:
            return .allow
        case .openExternally(let url):
            NSWorkspace.shared.open(url)
            return .cancel
        case .deny:
            // A refused load produces no finish/fail callback; don't leave `show` waiting forever.
            if !isPageLoaded {
                finishLoading(succeeded: false)
            }
            return .cancel
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoading(succeeded: true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        Self.logger.error("Preview failed to load: \(error.localizedDescription)")
        finishLoading(succeeded: false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        Self.logger.error("Preview failed to start loading: \(error.localizedDescription)")
        finishLoading(succeeded: false)
    }
}
