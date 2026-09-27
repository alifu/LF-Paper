//
//  MarkdownExport.swift
//  LF-Paper
//

import Foundation

/// File › Export as HTML: the rendered Markdown as one standalone page with its styles inlined.
nonisolated enum MarkdownExport {
    /// Styles only: no scripts can run, images may come from anywhere (relative ones load next to the file).
    static let contentSecurityPolicy = "default-src 'none'; img-src * data:; style-src 'unsafe-inline'"

    static func html(markdown: String, title: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <title>\(escaped(title))</title>
        <style>\(PreviewPage.stylesheet)</style>
        </head>
        <body><article class="markdown-body">
        \(MarkdownRenderer.html(from: markdown))
        </article></body>
        </html>
        """
    }

    /// The first heading, or the file name without its extension.
    static func title(for markdown: String, fileName: String) -> String {
        MarkdownOutline.headings(in: markdown).first?.title ?? (fileName as NSString).deletingPathExtension
    }

    static func writeHTML(markdown: String, title: String, to url: URL) throws(AppError) {
        do {
            try html(markdown: markdown, title: title).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw AppError.from(error, url: url, fallback: AppError.writeFailed)
        }
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
