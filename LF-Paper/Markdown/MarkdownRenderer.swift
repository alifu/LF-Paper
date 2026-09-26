//
//  MarkdownRenderer.swift
//  LF-Paper
//

import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Markdown → HTML with cmark-gfm (GitHub's renderer): tables, task lists, strikethrough, autolinks.
///
/// Uses cmark's safe mode: raw HTML is dropped and `javascript:`-style links are removed.
/// The preview adds more layers on top (no page JavaScript, a strict CSP, blocked navigation).
nonisolated enum MarkdownRenderer {
    private static let extensionNames = ["table", "strikethrough", "autolink", "tasklist"]
    private static let options = CMARK_OPT_DEFAULT
    /// cmark registers its extensions once per process; `static let` makes that happen exactly once.
    private static let extensionsRegistered: Void = cmark_gfm_core_extensions_ensure_registered()

    /// Renders off the main thread so large documents don't stall typing.
    @concurrent
    static func renderHTML(_ markdown: String) async -> String {
        html(from: markdown)
    }

    static func html(from markdown: String) -> String {
        _ = extensionsRegistered
        // cmark only returns NULL when it runs out of memory; an empty preview is the sane fallback.
        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }

        for name in extensionNames {
            if let syntaxExtension = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, syntaxExtension)
            }
        }
        cmark_parser_feed(parser, markdown, markdown.utf8.count)

        guard let document = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(document) }
        guard let html = cmark_render_html(document, options, cmark_parser_get_syntax_extensions(parser)) else {
            return ""
        }
        defer { free(html) }
        return String(cString: html)
    }
}
