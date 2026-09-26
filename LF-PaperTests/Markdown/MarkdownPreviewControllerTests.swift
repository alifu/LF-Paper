//
//  MarkdownPreviewControllerTests.swift
//  LF-PaperTests
//

import AppKit
import Testing
import WebKit
@testable import LF_Paper

/// Drives the real WKWebView offscreen: pixels, content updates and the asset scheme.
@MainActor
final class MarkdownPreviewControllerTests {
    private static let size = NSSize(width: 500, height: 300)

    private let controller = MarkdownPreviewController()
    private let window: NSWindow
    private let folder: TemporaryDirectory

    init() throws {
        folder = try TemporaryDirectory()
        window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = controller.webView
        controller.workspaceRoot = folder.url
    }

    private func evaluate(_ script: String) async throws -> Any? {
        try await controller.webView.callAsyncJavaScript(script, contentWorld: .defaultClient)
    }

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func previewDrawsReadableText(appearanceName: NSAppearance.Name) async throws {
        window.appearance = NSAppearance(named: appearanceName)
        let markdown = "# Heading\n\n" + String(repeating: "Some **readable** body text WWWW MMMM.\n\n", count: 6)

        await controller.show(bodyHTML: MarkdownRenderer.html(from: markdown), documentFolder: folder.url)
        let snapshot = try await controller.webView.takeSnapshot(configuration: nil)

        let bitmap = try #require(snapshot.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let isDark = appearanceName == .darkAqua
        let textPixels = PixelCounter.count(in: bitmap) { isDark ? $0 > 0.6 : $0 < 0.4 }
        let backgroundPixels = PixelCounter.count(in: bitmap) { isDark ? $0 < 0.3 : $0 > 0.7 }
        #expect(textPixels > 300, "text should stand out")
        #expect(backgroundPixels > textPixels, "background should follow the \(appearanceName.rawValue) appearance")
    }

    @Test func showingNewHTMLForTheSameFolderReplacesTheContent() async throws {
        await controller.show(bodyHTML: "<p>first</p>", documentFolder: folder.url)

        await controller.show(bodyHTML: "<p>second</p>", documentFolder: folder.url)

        let text = try await evaluate("return document.getElementById('content').innerText") as? String
        #expect(text?.contains("second") == true)
        #expect(text?.contains("first") == false)
    }

    @Test func pageJavaScriptDoesNotRun() async throws {
        await controller.show(bodyHTML: #"<p id="p">unchanged</p><script>document.getElementById('p').innerText = 'ran'</script>"#, documentFolder: folder.url)

        let text = try await evaluate("return document.getElementById('p').innerText") as? String
        #expect(text == "unchanged")
    }

    private func imageLoads(_ source: String) async throws -> Bool {
        await controller.show(bodyHTML: #"<img id="i" src="\#(source)">"#, documentFolder: folder.url)
        let width = try await evaluate("""
            const img = document.getElementById('i');
            if (!img.complete) { await new Promise(done => { img.onload = done; img.onerror = done; }); }
            return img.naturalWidth;
            """) as? Int
        return (width ?? 0) > 0
    }

    private func writePNG(to url: URL) throws {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }

    @Test func relativeImagesInsideTheWorkspaceLoad() async throws {
        try writePNG(to: try folder.makeFolder("img").appending(path: "pic.png"))

        #expect(try await imageLoads("img/pic.png"))
    }

    @Test func imagesOutsideTheWorkspaceDoNotLoad() async throws {
        let outside = try TemporaryDirectory()
        try writePNG(to: outside.url.appending(path: "secret.png"))

        #expect(try await !imageLoads("../\(outside.url.lastPathComponent)/secret.png"))
    }
}

/// Counts pixels by brightness, sampling every other pixel.
enum PixelCounter {
    static func count(in bitmap: NSBitmapImageRep, matching predicate: (CGFloat) -> Bool) -> Int {
        var count = 0
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if predicate(color.brightnessComponent) { count += 1 }
            }
        }
        return count
    }
}
