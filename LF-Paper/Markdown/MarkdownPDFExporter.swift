//
//  MarkdownPDFExporter.swift
//  LF-Paper
//

import AppKit
import Synchronization
import WebKit

/// File › Export as PDF: prints the rendered Markdown to a paginated PDF with page margins.
/// Uses its own offscreen web view (light appearance, page JavaScript off) and the preview's image
/// handler, so images from the workspace appear as they do in the preview.
final class MarkdownPDFExporter: NSObject {
    /// Three quarters of an inch on every side.
    private static let margin: CGFloat = 54
    private static let printTimeout: Duration = .seconds(60)
    /// Wide enough for the preview's layout; the print scales it to the page width.
    private static let layoutSize = NSSize(width: 800, height: 1000)
    private static let waitForImages = """
        await Promise.all([...document.images].map(image => image.complete ? null
            : new Promise(done => { image.onload = done; image.onerror = done; })));
        """

    private let webView: WKWebView
    private let window: NSWindow
    private let assetHandler = PreviewAssetSchemeHandler()
    private var loadContinuation: CheckedContinuation<Bool, Never>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.setURLSchemeHandler(assetHandler, forURLScheme: PreviewAssets.scheme)
        webView = WKWebView(frame: NSRect(origin: .zero, size: Self.layoutSize), configuration: configuration)
        // Paper is white: always print the light colours.
        webView.appearance = NSAppearance(named: .aqua)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.layoutSize), styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        super.init()
        webView.navigationDelegate = self
    }

    func write(markdown: String, documentFolder: URL, workspaceRoot: URL?, to url: URL) async throws(AppError) {
        assetHandler.root = workspaceRoot
        let body = await MarkdownRenderer.renderHTML(markdown)
        guard await load(PreviewPage.html(body: body), base: PreviewAssets.baseURL(for: documentFolder)) else {
            throw .writeFailed(url)
        }
        _ = try? await webView.callAsyncJavaScript(Self.waitForImages, contentWorld: .defaultClient)
        guard await print(to: url), FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw .writeFailed(url)
        }
    }

    private func load(_ html: String, base: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            loadContinuation = continuation
            webView.loadHTMLString(html, baseURL: base)
        }
    }

    /// Prints without blocking: `NSPrintOperation.run()` spins the main thread while WebKit needs it
    /// to lay out the pages, and never returns. `runModal(for:…)` reports back through a callback.
    private func print(to url: URL) async -> Bool {
        let info = NSPrintInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        info.topMargin = Self.margin
        info.bottomMargin = Self.margin
        info.leftMargin = Self.margin
        info.rightMargin = Self.margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false

        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        // WebKit's print view needs a frame, or the pages come out blank.
        operation.view?.frame = webView.bounds

        let completion = PrintCompletion()
        return await withCheckedContinuation { continuation in
            completion.start(continuation)
            operation.runModal(
                for: window,
                delegate: completion,
                didRun: #selector(PrintCompletion.printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil
            )
            // Never leave an export hanging: give up after a while.
            Task { [completion] in
                try? await Task.sleep(for: Self.printTimeout)
                completion.finish(false)
            }
        }
    }

    private func finishLoading(_ succeeded: Bool) {
        loadContinuation?.resume(returning: succeeded)
        loadContinuation = nil
    }
}

extension MarkdownPDFExporter: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoading(true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        finishLoading(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        finishLoading(false)
    }
}

/// Receives `NSPrintOperation`'s completion callback (an Objective-C selector) and resumes the
/// waiting export once, whichever comes first: the callback or the timeout. AppKit calls back on its
/// print thread and the timeout fires on the main thread, so the continuation is behind a lock.
nonisolated private final class PrintCompletion: NSObject, Sendable {
    private let continuation = Mutex<CheckedContinuation<Bool, Never>?>(nil)

    func start(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation.withLock { $0 = continuation }
    }

    @objc func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        finish(success)
    }

    func finish(_ success: Bool) {
        let waiting = continuation.withLock { stored in
            defer { stored = nil }
            return stored
        }
        waiting?.resume(returning: success)
    }
}
