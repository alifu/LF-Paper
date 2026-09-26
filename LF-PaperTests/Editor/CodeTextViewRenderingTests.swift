//
//  CodeTextViewRenderingTests.swift
//  LF-PaperTests
//

import AppKit
import SwiftUI
import Testing
@testable import LF_Paper

/// Renders the editor offscreen and checks that text pixels actually appear.
/// Regression: the line-number ruler (unclipped since macOS 14) painted over the text, leaving the editor blank.
@MainActor
struct CodeTextViewRenderingTests {
    private static let size = NSSize(width: 500, height: 300)

    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        return view.subviews.lazy.compactMap(findTextView(in:)).first
    }

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func editorDrawsReadableText(appearanceName: NSAppearance.Name) throws {
        let editor = CodeTextView(
            text: String(repeating: "Hello WWWW MMMM ████\n", count: 8),
            documentID: UUID(),
            fileKind: nil,
            onTextChange: { _ in }
        )
        let hostingView = NSHostingView(rootView: editor.frame(width: Self.size.width, height: Self.size.height))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearanceName)
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()

        let textView = try #require(findTextView(in: hostingView))
        let scrollView = try #require(textView.enclosingScrollView)
        let diagnostics = ("""
        [render \(appearanceName.rawValue)] scroll=\(scrollView.frame) clip=\(scrollView.contentView.frame) \
        text=\(textView.frame) container=\(textView.textContainer?.containerSize ?? .zero) \
        used=\(textView.layoutManager.map { $0.usedRect(for: textView.textContainer!) } ?? .zero) \
        chars=\(textView.string.count) inset=\(textView.textContainerInset) origin=\(textView.textContainerOrigin) \
        visible=\(textView.visibleRect) hidden=\(textView.isHiddenOrHasHiddenAncestor) \
        rulerThickness=\(scrollView.verticalRulerView?.ruleThickness ?? -1)
        """)

        let bitmap = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let isDark = appearanceName == .darkAqua
        let contrastingPixels = countPixels(in: bitmap) { brightness in
            isDark ? brightness > 0.6 : brightness < 0.4
        }

        #expect(textView.frame.width > 0 && textView.frame.height > 0)
        #expect(contrastingPixels > 500, "text should stand out from the background. \(diagnostics)")
    }

    /// Same check without SwiftUI, with and without the ruler, to tell hosting problems from ruler problems.
    @Test(arguments: [true, false])
    func appKitViewsAloneDrawText(withRuler: Bool) throws {
        let views = CodeTextView.makeEditorViews()
        views.scrollView.rulersVisible = withRuler
        let coordinator = CodeTextView.Coordinator { _ in }
        coordinator.attach(textView: views.textView, ruler: views.ruler)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = views.scrollView
        coordinator.update(text: String(repeating: "Hello WWWW MMMM ████\n", count: 8), documentID: UUID(), fileKind: nil)
        views.scrollView.layoutSubtreeIfNeeded()

        let bitmap = try #require(views.scrollView.bitmapImageRepForCachingDisplay(in: views.scrollView.bounds))
        views.scrollView.cacheDisplay(in: views.scrollView.bounds, to: bitmap)
        let dark = countPixels(in: bitmap) { $0 < 0.4 }
        #expect(dark > 500, "ruler=\(withRuler) dark pixels=\(dark) visible=\(views.textView.visibleRect) clip=\(views.scrollView.contentView.frame)")
    }

    private func countPixels(in bitmap: NSBitmapImageRep, matching predicate: (CGFloat) -> Bool) -> Int {
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
