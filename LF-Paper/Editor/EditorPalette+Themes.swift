//
//  EditorPalette+Themes.swift
//  LF-Paper
//

import AppKit

/// One theme variant as hex; the names say which token kinds use each colour.
nonisolated struct ThemeColors: Codable, Equatable, Sendable {
    var background, text, cursor, selection, currentLine, gutter: String
    /// Headings, JSON keys and `true`/`false`/`null`.
    var heading: String
    /// Bold, italic and links.
    var emphasis: String
    /// Strings and inline code.
    var string: String
    var comment, keyword, number: String
}

/// The user's colours, for the editor in light mode and in dark mode. Stored as JSON in the settings.
nonisolated struct CustomTheme: Codable, Equatable, Sendable {
    var light: ThemeColors
    var dark: ThemeColors

    /// Where a new custom theme starts: GitHub.
    static let standard = CustomTheme(light: EditorPalette.githubLightColors, dark: EditorPalette.githubDarkColors)

    init(light: ThemeColors, dark: ThemeColors) {
        self.light = light
        self.dark = dark
    }

    /// `nil` for empty or unreadable text, so callers fall back to `standard`.
    init?(json: String) {
        guard let theme = try? JSONDecoder().decode(CustomTheme.self, from: Data(json.utf8)) else { return nil }
        self = theme
    }

    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

nonisolated extension EditorPalette {
    /// `nil` if any colour isn't valid hex.
    init?(colors: ThemeColors) {
        func hex(_ value: String) -> HexColor? { HexColor(value) }
        guard let background = hex(colors.background), let text = hex(colors.text), let cursor = hex(colors.cursor),
              let selection = hex(colors.selection), let currentLine = hex(colors.currentLine),
              let gutter = hex(colors.gutter), let heading = hex(colors.heading), let emphasis = hex(colors.emphasis),
              let string = hex(colors.string), let comment = hex(colors.comment), let keyword = hex(colors.keyword),
              let number = hex(colors.number)
        else { return nil }
        self.init(
            background: background.nsColor,
            text: text.nsColor,
            cursor: cursor.nsColor,
            selection: selection.nsColor,
            selectedText: nil,
            currentLine: currentLine.nsColor,
            gutterText: gutter.nsColor,
            tokens: [
                .heading: TokenStyle(color: heading.nsColor, trait: .bold),
                .strong: TokenStyle(color: emphasis.nsColor, trait: .bold),
                .emphasis: TokenStyle(color: emphasis.nsColor, trait: .italic),
                .code: TokenStyle(color: string.nsColor),
                .link: TokenStyle(color: emphasis.nsColor),
                .quote: TokenStyle(color: comment.nsColor),
                .comment: TokenStyle(color: comment.nsColor),
                .listMarker: TokenStyle(color: keyword.nsColor),
                .key: TokenStyle(color: heading.nsColor),
                .string: TokenStyle(color: string.nsColor),
                .number: TokenStyle(color: number.nsColor),
                .literal: TokenStyle(color: heading.nsColor),
                .punctuation: TokenStyle(color: text.withAlpha(0.6).nsColor),
                .keyword: TokenStyle(color: keyword.nsColor, trait: .bold),
            ]
        )
    }

    /// The colours below are written here and covered by tests, so they always parse.
    private static func builtIn(_ colors: ThemeColors) -> EditorPalette {
        EditorPalette(colors: colors)!
    }

    // MARK: GitHub

    /// Rainglow's GitHub (github.json) by Dayle Rees, MIT licensed, with its comments lightened
    /// from `#555555` to be readable on its background (1.6:1 → 3.7:1).
    static let githubDarkColors = ThemeColors(
        background: "#333333", text: "#ffffff", cursor: "#ffffff", selection: "#00808055",
        currentLine: "#3b3b3b", gutter: "#666666", heading: "#66c4c4", emphasis: "#7385bc",
        string: "#e53d67", comment: "#8a8a8a", keyword: "#cccccc", number: "#e53d67"
    )

    /// Rainglow's GitHub Light (github-light.json), with its comments darkened from `#b8b6b1`
    /// to be readable on white (2.0:1 → 3.6:1).
    static let githubLightColors = ThemeColors(
        background: "#ffffff", text: "#555555", cursor: "#444444", selection: "#00808033",
        currentLine: "#f7f7f7", gutter: "#cccccc", heading: "#008080", emphasis: "#445588",
        string: "#dd1144", comment: "#8a8882", keyword: "#555555", number: "#dd1144"
    )

    static let githubDark = builtIn(githubDarkColors)
    static let githubLight = builtIn(githubLightColors)

    // MARK: Hyrule

    /// Rainglow's Hyrule (hyrule.json) by Dayle Rees, MIT licensed.
    static let hyruleDark = builtIn(ThemeColors(
        background: "#2d2c2b", text: "#c0d5c1", cursor: "#f8f8f0", selection: "#569e1655",
        currentLine: "#353432", gutter: "#615f5d", heading: "#569e16", emphasis: "#f5c504",
        string: "#ce830d", comment: "#716d6a", keyword: "#90c93f", number: "#f5c504"
    ))

    /// Rainglow's Hyrule Light (hyrule-light.json), with its three faintest colours darkened to be
    /// readable on its background: strings `#ce830d` → `#8f5a06` (1.97:1 → 3.72:1), comments
    /// `#93a594` → `#556856` (1.68:1 → 3.86:1) and numbers `#f5c504` → `#6b5500` (1.05:1 → 4.63:1).
    static let hyruleLight = builtIn(ThemeColors(
        background: "#c0d5c1", text: "#2d2c2b", cursor: "#222222", selection: "#569e1633",
        currentLine: "#b7cfb8", gutter: "#83ac85", heading: "#407710", emphasis: "#b7950c",
        string: "#8f5a06", comment: "#556856", keyword: "#68912e", number: "#6b5500"
    ))
}
