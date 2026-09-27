//
//  MarkdownExportTests.swift
//  LF-PaperTests
//

import AppKit
import PDFKit
import Testing
@testable import LF_Paper

/// File › Export as HTML / PDF.
@MainActor
struct MarkdownExportTests {
    // MARK: HTML

    @Test func htmlIsOneStandaloneStyledPage() {
        let html = MarkdownExport.html(markdown: "# Notes\n\nSome **bold** text.", title: "Notes")

        #expect(html.hasPrefix("<!doctype html>"))
        #expect(html.contains("<title>Notes</title>"))
        #expect(html.contains("<style>"))
        #expect(html.contains("<h1>Notes</h1>"))
        #expect(html.contains("<strong>bold</strong>"))
        #expect(!html.contains("data-sourcepos")) // preview-only markup stays out
    }

    @Test func htmlCannotRunScripts() {
        let html = MarkdownExport.html(markdown: "Hi <script>alert(1)</script> [x](javascript:alert(1))", title: "x")

        #expect(!html.contains("<script"))
        #expect(!html.contains("javascript:"))
        #expect(html.contains("default-src 'none'")) // and no script-src at all
        #expect(!html.contains("script-src"))
    }

    @Test func theTitleIsEscaped() {
        #expect(MarkdownExport.html(markdown: "", title: "<b>&</b>").contains("<title>&lt;b&gt;&amp;&lt;/b&gt;</title>"))
    }

    @Test func theTitleIsTheFirstHeadingOrTheFileName() {
        #expect(MarkdownExport.title(for: "Intro\n\n## Setup\n\n# Later", fileName: "notes.md") == "Setup")
        #expect(MarkdownExport.title(for: "No headings here.", fileName: "notes.md") == "notes")
    }

    @Test func htmlIsWrittenToTheChosenFile() throws {
        let folder = try TemporaryDirectory()
        let url = folder.url.appending(path: "notes.html")

        try MarkdownExport.writeHTML(markdown: "# Notes", title: "Notes", to: url)

        #expect(try String(contentsOf: url, encoding: .utf8).contains("<h1>Notes</h1>"))
    }

    // MARK: PDF

    @Test func pdfHasPagesMarginsAndTheText() async throws {
        let folder = try TemporaryDirectory()
        let markdown = "# Report\n\n" + (1...120).map { "Paragraph \($0) of the report." }.joined(separator: "\n\n")
        let url = folder.url.appending(path: "report.pdf")

        try await MarkdownPDFExporter().write(markdown: markdown, documentFolder: folder.url, workspaceRoot: folder.url, to: url)

        let pdf = try #require(PDFDocument(url: url))
        #expect(pdf.pageCount >= 2, "long documents are split into pages")
        let text = pdf.string ?? ""
        #expect(text.contains("Report"))
        #expect(text.contains("Paragraph 120"))

        let page = try #require(pdf.page(at: 0))
        let thumbnail = page.thumbnail(of: NSSize(width: 425, height: 550), for: .mediaBox)
        if let tiff = thumbnail.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
            try OffscreenRenderer.attach(bitmap, named: "pdf-first-page.png")
        }
        let bounds = page.bounds(for: .mediaBox)
        #expect(bounds.height > bounds.width, "portrait pages")
        let firstCharacter = page.characterBounds(at: 0)
        #expect(firstCharacter.minX >= 30, "the page has a left margin (text starts at \(firstCharacter.minX))")
        #expect(firstCharacter.maxY <= bounds.height - 30, "the page has a top margin")
    }
}
