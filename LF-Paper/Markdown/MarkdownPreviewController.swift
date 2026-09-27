//
//  MarkdownPreviewController.swift
//  LF-Paper
//

import AppKit
import os
import WebKit

/// Owns the preview's `WKWebView`. It loads the page once per folder, then swaps in new HTML
/// so the scroll position survives edits. Page JavaScript is off; links open in the browser.
///
/// Scroll sync: blocks carry their source line (`data-sourcepos`). The app reads where they are
/// and scrolls the page itself, and a listener in the app's own script world (which the page can't
/// see or call) reports where the reader scrolls.
final class MarkdownPreviewController: NSObject {
    private struct RenderRequest: Equatable {
        let markdown: String
        let documentURL: URL
    }

    /// Pause after typing before re-rendering, so fast typing doesn't queue up renders.
    private static let renderDelay: Duration = .milliseconds(150)
    private static let logger = Logger(subsystem: "AppWork.LF-Paper", category: "Preview")
    private static let scrollMessageName = "previewScroll"
    /// Block positions change when images load or text reflows; re-read them at most this often.
    private static let anchorLifetime: Duration = .milliseconds(500)
    /// A reported offset this close to where the app just scrolled is that scroll's echo.
    private static let echoTolerance = 1.0
    /// After the app scrolls, reports this soon are its echo even if the page clamped the offset.
    private static let echoWindow: Duration = .milliseconds(150)
    private static let scrollListener = """
        window.addEventListener('scroll', () => {
            window.webkit.messageHandlers.\(scrollMessageName).postMessage(window.scrollY);
        }, { passive: true });
        """
    private static let anchorsScript = """
        return [...document.querySelectorAll('[data-sourcepos]')].map(element => [
            parseInt(element.getAttribute('data-sourcepos'), 10),
            element.getBoundingClientRect().top + window.scrollY
        ]);
        """

    let webView: WKWebView
    private let assetHandler: PreviewAssetSchemeHandler
    private var pageURL: URL?
    private var isPageLoaded = false
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []
    private var lastRequest: RenderRequest?
    private var renderTask: Task<Void, Never>?

    /// Where the reader scrolled, as a (fractional) source line.
    var onScroll: (Double) -> Void = { _ in }
    /// The scroll in progress; tests await it.
    private(set) var scrollTask: Task<Void, Never>?
    /// Handling of the latest scroll report; tests await it.
    private(set) var scrollReportTask: Task<Void, Never>?
    /// The last scroll target taken from the editor, so SwiftUI updates don't repeat it.
    var lastScrollTargetID: UUID?
    private var pendingScrollLine: Double?
    private var anchors: [PreviewAnchor]?
    private var anchorsRead = ContinuousClock.now
    private var anchorsWidth: CGFloat = 0
    private var lastScrolledOffset: Double?
    private var ignoresScrollReportsUntil = ContinuousClock.now

    override init() {
        let assetHandler = PreviewAssetSchemeHandler()
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.setURLSchemeHandler(assetHandler, forURLScheme: PreviewAssets.scheme)
        let messages = ScrollMessageHandler()
        configuration.userContentController.add(messages, contentWorld: .defaultClient, name: Self.scrollMessageName)
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.scrollListener,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: .defaultClient
        ))
        self.assetHandler = assetHandler
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        messages.controller = self
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

    // MARK: Scroll sync

    /// Scrolls so the block on this (fractional) source line is at the top. Requests that arrive
    /// while one is running are merged: only the latest line is scrolled to next.
    func scroll(toLine line: Double) {
        pendingScrollLine = line
        guard scrollTask == nil else { return }
        scrollTask = Task {
            while let line = pendingScrollLine {
                pendingScrollLine = nil
                guard isPageLoaded else { break }
                let offset = PreviewScrollMapping.offset(forLine: line, anchors: await currentAnchors())
                // The page's scroll event can arrive before `scrollPage` returns, so expect the echo
                // from now on: at the requested offset, or clamped to the end within a short while.
                lastScrolledOffset = offset
                ignoresScrollReportsUntil = .now + Self.echoWindow
                lastScrolledOffset = await scrollPage(to: offset) ?? offset
            }
            scrollTask = nil
        }
    }

    /// The page's scroll listener reports each new offset here.
    func previewDidScroll(toOffset offset: Double) {
        if let lastScrolledOffset, abs(offset - lastScrolledOffset) < Self.echoTolerance {
            return // the echo of our own scroll
        }
        guard ContinuousClock.now >= ignoresScrollReportsUntil else { return }
        lastScrolledOffset = nil
        scrollReportTask = Task {
            let anchors = await currentAnchors()
            guard !anchors.isEmpty else { return }
            onScroll(PreviewScrollMapping.line(forOffset: offset, anchors: anchors))
        }
    }

    private func scrollPage(to offset: Double) async -> Double? {
        do {
            let actual = try await webView.callAsyncJavaScript(
                "window.scrollTo(0, y); return window.scrollY;",
                arguments: ["y": offset],
                contentWorld: .defaultClient
            )
            return (actual as? NSNumber)?.doubleValue
        } catch {
            Self.logger.error("Could not scroll the preview: \(error.localizedDescription)")
            return nil
        }
    }

    /// Where each block starts on the page; re-read after changes, resizes, or a short while.
    private func currentAnchors() async -> [PreviewAnchor] {
        let width = webView.bounds.width
        if let anchors, width == anchorsWidth, ContinuousClock.now - anchorsRead < Self.anchorLifetime {
            return anchors
        }
        let rows = (try? await webView.callAsyncJavaScript(Self.anchorsScript, contentWorld: .defaultClient)) as? [[Any]] ?? []
        let read = rows.compactMap { row -> PreviewAnchor? in
            guard row.count == 2,
                  let line = (row[0] as? NSNumber)?.intValue,
                  let offset = (row[1] as? NSNumber)?.doubleValue
            else { return nil }
            return PreviewAnchor(line: line, offset: offset)
        }
        let normalized = PreviewScrollMapping.normalized(read)
        anchors = normalized
        anchorsWidth = width
        anchorsRead = .now
        return normalized
    }

    private func replaceContent(with bodyHTML: String, scrollsToTop: Bool) async {
        anchors = nil
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
        anchors = nil
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

/// Receives the page's scroll reports. Separate and weak: the web view's content controller keeps
/// its message handlers alive, which would otherwise keep the preview controller alive forever.
private final class ScrollMessageHandler: NSObject, WKScriptMessageHandler {
    weak var controller: MarkdownPreviewController?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let offset = (message.body as? NSNumber)?.doubleValue else { return }
        controller?.previewDidScroll(toOffset: offset)
    }
}
