//
//  DifferenceListRenderingTests.swift
//  LF-PaperTests
//

import AppKit
import SwiftUI
import Testing
@testable import LF_Paper

/// Renders the list of structural differences offscreen, in dark and light mode.
@MainActor
struct DifferenceListRenderingTests {
    private static let size = NSSize(width: 420, height: 220)

    private func differences(from old: String, to new: String) throws -> [JSONDifference] {
        JSONDiff.differences(from: try JSONParser.parse(old).value, to: try JSONParser.parse(new).value)
    }

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func listsChangedAddedAndRemovedValues(appearance: NSAppearance.Name) throws {
        let differences = try differences(
            from: #"{"name": "Ada", "age": 36, "city": "London"}"#,
            to: #"{"name": "Ada L.", "age": 36, "email": "ada@example.com"}"#
        )
        #expect(Set(differences.map(\.kind)) == [.changed, .added, .removed])

        let bitmap = try OffscreenRenderer.render(DifferenceListView(differences: differences), size: Self.size, appearance: appearance)
        try OffscreenRenderer.attach(bitmap, named: "differences-\(appearance.rawValue).png")

        let content = OffscreenRenderer.contentPixels(in: bitmap, appearance: appearance)
        let blank = try OffscreenRenderer.blankContentPixels(size: Self.size, appearance: appearance)
        #expect(content > blank + 60, "rows should be visible (blank: \(blank), list: \(content))")
    }

    @Test func saysSoWhenThereAreNoDifferences() throws {
        let bitmap = try OffscreenRenderer.render(DifferenceListView(differences: []), size: Self.size, appearance: .darkAqua)
        try OffscreenRenderer.attach(bitmap, named: "differences-none.png")

        let content = OffscreenRenderer.contentPixels(in: bitmap, appearance: .darkAqua)
        let blank = try OffscreenRenderer.blankContentPixels(size: Self.size, appearance: .darkAqua)
        #expect(content > blank + 30, "the empty state should be visible (blank: \(blank), view: \(content))")
    }
}
