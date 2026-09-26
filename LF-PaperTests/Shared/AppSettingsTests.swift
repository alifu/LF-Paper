//
//  AppSettingsTests.swift
//  LF-PaperTests
//

import AppKit
import Testing
@testable import LF_Paper

struct AppSettingsTests {
    @Test func fontSizeStaysWithinTheAllowedRange() {
        #expect(AppSettings.clampedFontSize(4) == AppSettings.fontSizeRange.lowerBound)
        #expect(AppSettings.clampedFontSize(15) == 15)
        #expect(AppSettings.clampedFontSize(99) == AppSettings.fontSizeRange.upperBound)
    }

    @Test func zoomingStepsTheFontSizeAndStopsAtTheLimits() {
        #expect(AppSettings.fontSize(13, zoomed: .bigger) == 14)
        #expect(AppSettings.fontSize(13, zoomed: .smaller) == 12)
        #expect(AppSettings.fontSize(20, zoomed: .actualSize) == AppSettings.defaultFontSize)
        #expect(AppSettings.fontSize(AppSettings.fontSizeRange.upperBound, zoomed: .bigger) == AppSettings.fontSizeRange.upperBound)
        #expect(AppSettings.fontSize(AppSettings.fontSizeRange.lowerBound, zoomed: .smaller) == AppSettings.fontSizeRange.lowerBound)
    }

    @Test(arguments: [
        (JSONIndentationSetting.twoSpaces, JSONFormatter.Indentation.spaces(2)),
        (.fourSpaces, .spaces(4)),
        (.tab, .tab),
    ])
    func indentationSettingsMapToTheFormatter(setting: JSONIndentationSetting, expected: JSONFormatter.Indentation) {
        #expect(setting.indentation == expected)
    }

    @Test func appearanceSettingsMapToAppKitAppearances() {
        #expect(AppAppearance.system.appearanceName == nil)
        #expect(AppAppearance.light.appearanceName == .aqua)
        #expect(AppAppearance.dark.appearanceName == .darkAqua)
    }

    @Test func settingsHaveStableStorageValues() {
        // Changing these would silently reset people's settings.
        #expect(AppAppearance.allCases.map(\.rawValue) == ["system", "light", "dark"])
        #expect(JSONIndentationSetting.allCases.map(\.rawValue) == ["twoSpaces", "fourSpaces", "tab"])
    }
}
