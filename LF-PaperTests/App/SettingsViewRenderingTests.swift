//
//  SettingsViewRenderingTests.swift
//  LF-PaperTests
//

import AppKit
import SwiftUI
import Testing
@testable import LF_Paper

/// Renders the Settings window offscreen, in dark and light mode. It only reads the settings.
@MainActor
struct SettingsViewRenderingTests {
    private static let size = NSSize(width: 420, height: 290)

    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func showsEverySetting(appearance: NSAppearance.Name) throws {
        let bitmap = try OffscreenRenderer.render(SettingsView(), size: Self.size, appearance: appearance)
        try OffscreenRenderer.attach(bitmap, named: "settings-\(appearance.rawValue).png")

        let content = OffscreenRenderer.contentPixels(in: bitmap, appearance: appearance)
        let blank = try OffscreenRenderer.blankContentPixels(size: Self.size, appearance: appearance)
        #expect(content > blank + 100, "labels and controls should be visible (blank: \(blank), settings: \(content))")
    }
}
