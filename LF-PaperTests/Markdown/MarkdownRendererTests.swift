//
//  MarkdownRendererTests.swift
//  LF-PaperTests
//

import Testing
@testable import LF_Paper

struct MarkdownRendererTests {
    private func html(_ markdown: String) -> String {
        MarkdownRenderer.html(from: markdown)
    }

    @Test func rendersHeadingsWithInlineFormatting() {
        #expect(html("# Hello *world*").contains("<h1>Hello <em>world</em></h1>"))
    }

    @Test func escapesSpecialCharactersInText() {
        #expect(html("a < b & c").contains("a &lt; b &amp; c"))
    }

    @Test func codeBlocksShowHTMLAsTextWithTheLanguageClass() {
        let rendered = html("```html\n<div>x</div>\n```")

        #expect(rendered.contains(#"<pre><code class="language-html">&lt;div&gt;x&lt;/div&gt;"#))
    }

    @Test func rendersTables() {
        let rendered = html("| A | B |\n|---|---|\n| 1 | 2 |")

        #expect(rendered.contains("<table>"))
        #expect(rendered.contains("<th>A</th>"))
        #expect(rendered.contains("<td>2</td>"))
    }

    @Test func rendersTaskListCheckboxes() {
        let rendered = html("- [x] done\n- [ ] todo")

        #expect(rendered.contains(#"type="checkbox""#))
        #expect(rendered.contains("checked"))
    }

    @Test func rendersStrikethroughAndAutolinks() {
        #expect(html("~~gone~~").contains("<del>gone</del>"))
        #expect(html("visit https://example.com today").contains(#"<a href="https://example.com">"#))
    }

    // MARK: Safety

    @Test func dropsRawHTML() {
        let rendered = html("<script>alert(1)</script>\n\ntext <img src=x onerror=alert(1)>")

        #expect(!rendered.contains("<script"))
        #expect(!rendered.contains("onerror"))
    }

    @Test func removesJavaScriptLinks() {
        #expect(!html("[click](javascript:alert(1))").contains("javascript:"))
    }

    @Test func emptyInputRendersNothing() {
        #expect(html("") == "")
    }
}
