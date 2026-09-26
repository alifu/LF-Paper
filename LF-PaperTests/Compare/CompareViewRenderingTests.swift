//
//  CompareViewRenderingTests.swift
//  LF-PaperTests
//

import AppKit
import SwiftUI
import Testing
@testable import LF_Paper

/// Renders the whole Compare window offscreen and checks the source cards sit at the top.
@MainActor
struct CompareViewRenderingTests {
    private static let size = NSSize(width: 1000, height: 650)
    /// The sources row has 10 pt of padding; anything much larger is an unwanted gap.
    private static let maximumTopInset = 16

    private func render(_ model: CompareModel) throws -> NSBitmapImageRep {
        let hostingView = NSHostingView(rootView: CompareView(model: model))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hostingView
        window.setContentSize(Self.size)
        hostingView.layoutSubtreeIfNeeded()
        let bitmap = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return bitmap
    }

    /// The first pixel row (from the top) that differs from the window background in the left margin column.
    private func firstContentRow(in bitmap: NSBitmapImageRep) throws -> Int {
        let x = 20 * max(bitmap.pixelsWide / Int(Self.size.width), 1) // inside the left card, left of its text
        let background = try #require(bitmap.colorAt(x: x, y: 0))
        for y in 0..<bitmap.pixelsHigh {
            guard let color = bitmap.colorAt(x: x, y: y) else { continue }
            if abs(color.brightnessComponent - background.brightnessComponent) > 0.02 { return y }
        }
        return bitmap.pixelsHigh
    }

    @Test(arguments: [false, true])
    func sourceCardsStartAtTheTopOfTheWindow(isCompared: Bool) async throws {
        let model = CompareModel()
        if isCompared {
            model.setSide(.left, title: "a.json", text: #"{"a":1}"#)
            model.setSide(.right, title: "b.json", text: #"{"a":2}"#)
            try await Task.sleep(for: .milliseconds(600))
        }

        let bitmap = try render(model)
        Attachment.record(try #require(bitmap.representation(using: .png, properties: [:])), named: "compare-\(isCompared ? "compared" : "empty").png")

        let scale = max(bitmap.pixelsHigh / Int(Self.size.height), 1)
        let top = try firstContentRow(in: bitmap) / scale
        #expect(top <= Self.maximumTopInset, "source cards start \(top) pt below the top")
    }
}
