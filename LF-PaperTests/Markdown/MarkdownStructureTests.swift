//
//  MarkdownStructureTests.swift
//  LF-PaperTests
//

import Testing
@testable import LF_Paper

/// Source lines in the rendered HTML (for scroll sync), the mapping between editor lines and
/// preview offsets, and the heading outline.
struct MarkdownStructureTests {
    // MARK: Source positions

    @Test func previewHTMLMarksWhereEachBlockStarts() {
        let html = MarkdownRenderer.html(from: "# Title\n\nFirst paragraph.\n\n- item\n", includesSourcePositions: true)

        #expect(html.contains(#"<h1 data-sourcepos="1:1-1:7">"#))
        #expect(html.contains(#"<p data-sourcepos="3:1-3:16">"#))
        #expect(html.contains(#"<ul data-sourcepos="5:1-5:6">"#))
    }

    @Test func exportedHTMLHasNoSourcePositions() {
        #expect(!MarkdownRenderer.html(from: "# Title").contains("data-sourcepos"))
    }

    // MARK: Scroll mapping

    private let anchors = [
        PreviewAnchor(line: 1, offset: 0),
        PreviewAnchor(line: 5, offset: 100),
        PreviewAnchor(line: 9, offset: 300),
    ]

    @Test func linesBetweenBlocksMapProportionally() {
        #expect(PreviewScrollMapping.offset(forLine: 5, anchors: anchors) == 100)
        #expect(PreviewScrollMapping.offset(forLine: 3, anchors: anchors) == 50)
        #expect(PreviewScrollMapping.offset(forLine: 7, anchors: anchors) == 200)
    }

    @Test func offsetsMapBackToTheSameLines() {
        for line in [1.0, 2.5, 5, 6.25, 9] {
            let offset = PreviewScrollMapping.offset(forLine: line, anchors: anchors)
            #expect(abs(PreviewScrollMapping.line(forOffset: offset, anchors: anchors) - line) < 0.0001)
        }
    }

    @Test func beforeTheFirstAndAfterTheLastBlockStayAtTheEnds() {
        #expect(PreviewScrollMapping.offset(forLine: 0, anchors: anchors) == 0)
        #expect(PreviewScrollMapping.offset(forLine: 40, anchors: anchors) == 300)
        #expect(PreviewScrollMapping.line(forOffset: -20, anchors: anchors) == 1)
        #expect(PreviewScrollMapping.line(forOffset: 900, anchors: anchors) == 9)
    }

    @Test func anchorsAreSortedAndNestedBlocksThatGoBackwardsAreDropped() {
        let messy = [
            PreviewAnchor(line: 9, offset: 300),
            PreviewAnchor(line: 1, offset: 0),
            PreviewAnchor(line: 5, offset: 100),
            PreviewAnchor(line: 5, offset: 104), // a list item starting on the list's line
            PreviewAnchor(line: 7, offset: 90), // laid out above an earlier line: ignored
        ]

        #expect(PreviewScrollMapping.normalized(messy) == anchors)
    }

    @Test func withoutAnchorsEverythingIsTheTop() {
        #expect(PreviewScrollMapping.offset(forLine: 12, anchors: []) == 0)
        #expect(PreviewScrollMapping.line(forOffset: 400, anchors: []) == 1)
    }

    // MARK: Outline

    @Test func findsATXAndSetextHeadingsWithTheirLevelsAndLines() {
        let markdown = """
            # Title

            Intro.

            Section
            -------

            ### Detail with `code` and *emphasis*
            """

        let headings = MarkdownOutline.headings(in: markdown)

        #expect(headings == [
            MarkdownHeading(level: 1, title: "Title", line: 1),
            MarkdownHeading(level: 2, title: "Section", line: 5),
            MarkdownHeading(level: 3, title: "Detail with code and emphasis", line: 8),
        ])
    }

    @Test func ignoresHashesInsideCodeBlocksAndQuotesOfCode() {
        let markdown = """
            ```sh
            # not a heading
            ```

                # indented code, not a heading

            ## Real
            """

        #expect(MarkdownOutline.headings(in: markdown).map(\.title) == ["Real"])
    }

    @Test func aDocumentWithoutHeadingsHasNoOutline() {
        #expect(MarkdownOutline.headings(in: "Just text.\n\nMore text.").isEmpty)
    }
}
