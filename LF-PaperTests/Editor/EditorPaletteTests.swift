//
//  EditorPaletteTests.swift
//  LF-PaperTests
//

import AppKit
import Testing
@testable import LF_Paper

/// Editor themes as data: hex colours, the System and Hyrule palettes, and their contrast.
struct EditorPaletteTests {
    // MARK: Hex colours

    @Test func parsesSixAndEightDigitHex() throws {
        let color = try #require(HexColor("#2d2c2b"))
        #expect(color == HexColor(red: 0x2d / 255, green: 0x2c / 255, blue: 0x2b / 255, alpha: 1))
        #expect(HexColor("c0d5c1") == HexColor("#C0D5C1"))
        #expect(try #require(HexColor("#569e1655")).alpha == Double(0x55) / 255)
    }

    @Test(arguments: ["", "#", "#12345", "#1234567", "#gggggg", "#2d2c2b0", "blue"])
    func rejectsInvalidHex(text: String) {
        #expect(HexColor(text) == nil)
    }

    @Test func alphaCanBeChanged() throws {
        let color = try #require(HexColor("#c0d5c1")).withAlpha(0.6)
        #expect(color.alpha == 0.6)
        #expect(color.red == Double(0xc0) / 255)
    }

    @Test func convertsToAnSRGBColor() throws {
        let color = try #require(HexColor("#ce830d")).nsColor
        #expect(color.colorSpace == .sRGB)
        #expect(abs(color.redComponent - Double(0xce) / 255) < 0.0001)
        #expect(abs(color.blueComponent - Double(0x0d) / 255) < 0.0001)
    }

    // MARK: Palettes

    @Test func hyruleDarkMatchesRainglow() {
        let palette = EditorPalette.hyruleDark
        #expect(palette.background == HexColor("#2d2c2b")?.nsColor)
        #expect(palette.text == HexColor("#c0d5c1")?.nsColor)
        #expect(palette.gutterText == HexColor("#615f5d")?.nsColor)
        #expect(palette.currentLine == HexColor("#353432")?.nsColor)
        #expect(palette.selection == HexColor("#569e1655")?.nsColor)
        #expect(palette.cursor == HexColor("#f8f8f0")?.nsColor)
        #expect(palette.style(for: .heading) == TokenStyle(color: HexColor("#569e16")?.nsColor, trait: .bold))
        #expect(palette.style(for: .strong) == TokenStyle(color: HexColor("#f5c504")?.nsColor, trait: .bold))
        #expect(palette.style(for: .emphasis) == TokenStyle(color: HexColor("#f5c504")?.nsColor, trait: .italic))
        #expect(palette.style(for: .comment).color == HexColor("#716d6a")?.nsColor)
        #expect(palette.style(for: .string).color == HexColor("#ce830d")?.nsColor)
        #expect(palette.style(for: .number).color == HexColor("#f5c504")?.nsColor)
        #expect(palette.style(for: .punctuation).color == HexColor("#c0d5c1")?.withAlpha(0.6).nsColor)
        #expect(palette.style(for: .keyword) == TokenStyle(color: HexColor("#90c93f")?.nsColor, trait: .bold))
    }

    /// Rainglow's values, except the three faintest, darkened to be readable.
    @Test func hyruleLightMatchesRainglowWithReadableFaintColours() {
        let palette = EditorPalette.hyruleLight
        #expect(palette.background == HexColor("#c0d5c1")?.nsColor)
        #expect(palette.text == HexColor("#2d2c2b")?.nsColor)
        #expect(palette.gutterText == HexColor("#83ac85")?.nsColor)
        #expect(palette.currentLine == HexColor("#b7cfb8")?.nsColor)
        #expect(palette.selection == HexColor("#569e1633")?.nsColor)
        #expect(palette.cursor == HexColor("#222222")?.nsColor)
        #expect(palette.style(for: .key).color == HexColor("#407710")?.nsColor)
        #expect(palette.style(for: .link).color == HexColor("#b7950c")?.nsColor)
        #expect(palette.style(for: .listMarker).color == HexColor("#68912e")?.nsColor)
        #expect(palette.style(for: .number).color == HexColor("#6b5500")?.nsColor) // Rainglow: #f5c504
        #expect(palette.style(for: .string).color == HexColor("#8f5a06")?.nsColor) // Rainglow: #ce830d
        #expect(palette.style(for: .code).color == HexColor("#8f5a06")?.nsColor)
        #expect(palette.style(for: .comment).color == HexColor("#556856")?.nsColor) // Rainglow: #93a594
        #expect(palette.style(for: .quote).color == HexColor("#556856")?.nsColor)
    }

    @Test func everyTokenHasAHyruleColour() {
        let kinds: [TokenKind] = [.heading, .strong, .emphasis, .code, .link, .quote, .listMarker, .key, .string, .number, .literal, .punctuation, .comment, .keyword]
        for palette in [EditorPalette.hyruleDark, .hyruleLight] {
            #expect(kinds.allSatisfy { palette.style(for: $0).color != nil })
        }
    }

    @Test func systemKeepsTheAdaptiveColours() {
        let palette = EditorPalette.system
        #expect(palette.background == .textBackgroundColor)
        #expect(palette.text == .textColor)
        #expect(palette.currentLine == nil) // no highlight, as before
        #expect(palette.style(for: .strong) == TokenStyle(color: nil, trait: .bold))
        #expect(palette.style(for: .string).color == .systemRed)
    }

    @Test func hyruleFollowsTheAppearance() {
        #expect(EditorPalette.palette(for: .hyrule, isDark: true) == .hyruleDark)
        #expect(EditorPalette.palette(for: .hyrule, isDark: false) == .hyruleLight)
        #expect(EditorPalette.palette(for: .system, isDark: true) == .system)
        #expect(EditorPalette.palette(for: .system, isDark: false) == .system)
    }

    // MARK: GitHub and custom themes

    @Test func githubDarkMatchesRainglowWithReadableComments() {
        let palette = EditorPalette.githubDark
        #expect(palette.background == HexColor("#333333")?.nsColor)
        #expect(palette.text == HexColor("#ffffff")?.nsColor)
        #expect(palette.currentLine == HexColor("#3b3b3b")?.nsColor)
        #expect(palette.selection == HexColor("#00808055")?.nsColor)
        #expect(palette.style(for: .key).color == HexColor("#66c4c4")?.nsColor)
        #expect(palette.style(for: .link).color == HexColor("#7385bc")?.nsColor)
        #expect(palette.style(for: .string).color == HexColor("#e53d67")?.nsColor)
        #expect(palette.style(for: .comment).color == HexColor("#8a8a8a")?.nsColor) // Rainglow: #555555
    }

    @Test func githubLightMatchesRainglowWithReadableComments() {
        let palette = EditorPalette.githubLight
        #expect(palette.background == HexColor("#ffffff")?.nsColor)
        #expect(palette.text == HexColor("#555555")?.nsColor)
        #expect(palette.style(for: .key).color == HexColor("#008080")?.nsColor)
        #expect(palette.style(for: .string).color == HexColor("#dd1144")?.nsColor)
        #expect(palette.style(for: .comment).color == HexColor("#8a8882")?.nsColor) // Rainglow: #b8b6b1
    }

    @Test func githubIsTheDefaultTheme() {
        #expect(AppSettings.defaultEditorTheme == .github)
        #expect(EditorPalette.palette(for: .github, isDark: true) == .githubDark)
        #expect(EditorPalette.palette(for: .github, isDark: false) == .githubLight)
    }

    @Test func githubCommentsAreReadable() throws {
        for (comment, background) in [("#8a8a8a", "#333333"), ("#8a8882", "#ffffff")] {
            let ratio = HexColor.contrastRatio(try #require(HexColor(comment)), try #require(HexColor(background)))
            #expect(ratio >= 3.5)
        }
    }

    @Test func customThemeUsesItsOwnColoursPerAppearance() {
        var theme = CustomTheme.standard
        theme.dark.background = "#101010"
        theme.light.string = "#123456"
        #expect(EditorPalette.palette(for: .custom, isDark: true, customTheme: theme).background == HexColor("#101010")?.nsColor)
        #expect(EditorPalette.palette(for: .custom, isDark: false, customTheme: theme).style(for: .string).color == HexColor("#123456")?.nsColor)
    }

    @Test func customThemeStartsAsGitHub() {
        #expect(EditorPalette.palette(for: .custom, isDark: true) == .githubDark)
        #expect(EditorPalette.palette(for: .custom, isDark: false) == .githubLight)
    }

    @Test func customThemeSurvivesTheSettingsRoundTrip() {
        var theme = CustomTheme.standard
        theme.light.keyword = "#abcdef"
        #expect(CustomTheme(json: theme.json) == theme)
    }

    @Test(arguments: ["", "not json", "{}", "{\"light\": 1}"])
    func unreadableCustomThemeIsNil(json: String) {
        #expect(CustomTheme(json: json) == nil)
    }

    @Test func aCustomThemeWithBadHexFallsBackToGitHub() {
        var theme = CustomTheme.standard
        theme.dark.text = "nope"
        #expect(EditorPalette(colors: theme.dark) == nil)
        #expect(EditorPalette.palette(for: .custom, isDark: true, customTheme: theme) == .githubDark)
    }

    @Test func hexStringRoundTrips() throws {
        #expect(try #require(HexColor("#2d2c2b")).hexString == "#2d2c2b")
        #expect(try #require(HexColor("#569e1655")).hexString == "#569e1655")
        #expect(HexColor(NSColor(srgbRed: 1, green: 0, blue: 0.5, alpha: 1))?.hexString == "#ff0080")
    }

    // MARK: Contrast (WCAG 2)

    @Test func contrastRatiosFollowWCAG() throws {
        let black = try #require(HexColor("#000000"))
        let white = try #require(HexColor("#ffffff"))
        #expect(abs(HexColor.contrastRatio(black, white) - 21) < 0.001)
        #expect(HexColor.contrastRatio(white, white) == 1)
        #expect(HexColor.contrastRatio(white, black) == HexColor.contrastRatio(black, white))
    }

    /// Recorded so a palette change that hurts legibility shows up. Text passes AA (4.5:1). Hyrule's
    /// dark comments are faithful to Rainglow (about 3:1); Hyrule Light's faint colours were darkened.
    @Test func hyruleContrastIsRecorded() throws {
        func ratio(_ foreground: String, on background: String) throws -> Double {
            HexColor.contrastRatio(try #require(HexColor(foreground)), try #require(HexColor(background)))
        }
        #expect(try ratio("#c0d5c1", on: "#2d2c2b") >= 7) // dark text: AAA
        #expect(try ratio("#2d2c2b", on: "#c0d5c1") >= 7) // light text: AAA
        #expect(try (2.5...3.5).contains(ratio("#716d6a", on: "#2d2c2b"))) // dark comments: about 3:1
        #expect(try ratio("#f5c504", on: "#2d2c2b") >= 7) // dark numbers
        #expect(try ratio("#f5c504", on: "#c0d5c1") < 2) // Rainglow's light numbers: nearly invisible
        #expect(try ratio("#6b5500", on: "#c0d5c1") >= 4.5) // so light numbers use this
        #expect(try ratio("#8f5a06", on: "#c0d5c1") >= 3.5) // light strings, from 1.97:1
        #expect(try ratio("#556856", on: "#c0d5c1") >= 3.5) // light comments, from 1.68:1
    }
}
