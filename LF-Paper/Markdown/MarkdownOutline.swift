//
//  MarkdownOutline.swift
//  LF-Paper
//

import Foundation
import cmark_gfm

/// One heading of a Markdown document.
nonisolated struct MarkdownHeading: Equatable, Sendable, Identifiable {
    let level: Int
    /// The heading's text without formatting.
    let title: String
    /// 1-based source line where the heading starts.
    let line: Int

    var id: Int { line }
}

/// The headings of a Markdown document, from cmark's syntax tree, so ATX (`# Title`) and Setext
/// (underlined) headings are found and `#` lines inside code blocks aren't.
nonisolated enum MarkdownOutline {
    static func headings(in markdown: String) -> [MarkdownHeading] {
        guard let parser = cmark_parser_new(CMARK_OPT_DEFAULT) else { return [] }
        defer { cmark_parser_free(parser) }
        cmark_parser_feed(parser, markdown, markdown.utf8.count)
        guard let document = cmark_parser_finish(parser) else { return [] }
        defer { cmark_node_free(document) }

        var headings: [MarkdownHeading] = []
        var child = cmark_node_first_child(document)
        while let node = child {
            // Headings are top-level blocks unless nested in quotes or lists, which outlines skip.
            if cmark_node_get_type(node) == CMARK_NODE_HEADING {
                headings.append(MarkdownHeading(
                    level: Int(cmark_node_get_heading_level(node)),
                    title: plainText(of: node).trimmingCharacters(in: .whitespaces),
                    line: Int(cmark_node_get_start_line(node))
                ))
            }
            child = cmark_node_next(node)
        }
        return headings
    }

    @concurrent
    static func headingsInBackground(_ markdown: String) async -> [MarkdownHeading] {
        headings(in: markdown)
    }

    /// The literal text inside a node (text and inline code), with line breaks as spaces.
    private static func plainText(of node: UnsafeMutablePointer<cmark_node>) -> String {
        switch cmark_node_get_type(node) {
        case CMARK_NODE_TEXT, CMARK_NODE_CODE:
            return cmark_node_get_literal(node).map { String(cString: $0) } ?? ""
        case CMARK_NODE_SOFTBREAK, CMARK_NODE_LINEBREAK:
            return " "
        default:
            var text = ""
            var child = cmark_node_first_child(node)
            while let current = child {
                text += plainText(of: current)
                child = cmark_node_next(current)
            }
            return text
        }
    }
}
