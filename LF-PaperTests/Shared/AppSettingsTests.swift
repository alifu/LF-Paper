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

    @Test func settingsHaveTitlesForThePickers() {
        #expect(AppAppearance.allCases.map(\.title) == ["System", "Light", "Dark"])
        #expect(JSONIndentationSetting.allCases.map(\.title) == ["2 Spaces", "4 Spaces", "Tab"])
        #expect(AppAppearance.allCases.map(\.id) == AppAppearance.allCases)
        #expect(JSONIndentationSetting.allCases.map(\.id) == JSONIndentationSetting.allCases)
    }

    @Test func closingAWindowAsksUnlessSetToSave() throws {
        let suiteName = "LFPaperTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let defaults = try #require(UserDefaults(suiteName: suiteName))

        #expect(UnsavedChangesOnClose.current(in: defaults) == .ask)
        defaults.set(UnsavedChangesOnClose.saveAutomatically.rawValue, forKey: AppSettings.Key.unsavedChangesOnClose)
        #expect(UnsavedChangesOnClose.current(in: defaults) == .saveAutomatically)
        defaults.set("something old", forKey: AppSettings.Key.unsavedChangesOnClose)
        #expect(UnsavedChangesOnClose.current(in: defaults) == .ask)
        #expect(UnsavedChangesOnClose.allCases.map(\.title) == ["Ask", "Save Automatically"])
    }

    @Test func linesDoNotWrapByDefault() {
        #expect(!AppSettings.defaultWrapsLines)
        #expect(AppSettings.Key.wrapsLines == "settings.wrapsLines") // changing it would reset people's choice
    }

    @Test func settingsHaveStableStorageValues() {
        // Changing these would silently reset people's settings.
        #expect(AppAppearance.allCases.map(\.rawValue) == ["system", "light", "dark"])
        #expect(JSONIndentationSetting.allCases.map(\.rawValue) == ["twoSpaces", "fourSpaces", "tab"])
        #expect(UnsavedChangesOnClose.allCases.map(\.rawValue) == ["ask", "saveAutomatically"])
    }
}
