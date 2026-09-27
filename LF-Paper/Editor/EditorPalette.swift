//
//  EditorPalette.swift
//  LF-Paper
//

import AppKit

/// An sRGB colour written as hex, as editor themes are.
nonisolated struct HexColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `#rrggbb` or `#rrggbbaa`, with or without the `#`.
    init?(_ hex: String) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        let channels = digits.count == 8 ? value : value << 8 | 0xff
        func channel(_ shift: UInt64) -> Double { Double((channels >> shift) & 0xff) / 255 }
        self.init(red: channel(24), green: channel(16), blue: channel(8), alpha: channel(0))
    }

    func withAlpha(_ alpha: Double) -> HexColor {
        HexColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// WCAG 2 relative luminance (alpha ignored).
    var luminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2 contrast ratio, from 1 (none) to 21 (black on white). AA asks 4.5 for body text.
    static func contrastRatio(_ first: HexColor, _ second: HexColor) -> Double {
        let (lighter, darker) = first.luminance > second.luminance ? (first, second) : (second, first)
        return (lighter.luminance + 0.05) / (darker.luminance + 0.05)
    }
}

/// How a syntax token is drawn: a colour (`nil` keeps the text colour) and a font trait.
nonisolated struct TokenStyle: Equatable, @unchecked Sendable {
    enum Trait: Sendable {
        case regular
        case bold
        case italic
    }

    let color: NSColor?
    let trait: Trait

    init(color: NSColor?, trait: Trait = .regular) {
        self.color = color
        self.trait = trait
    }
}

/// Settings › Editor theme.
nonisolated enum EditorThemeSetting: String, CaseIterable, Identifiable, Sendable {
    /// The system's colours, which follow light and dark mode.
    case system
    /// Rainglow's Hyrule, with Hyrule Light in light mode.
    case hyrule

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .hyrule: "Hyrule"
        }
    }
}

/// The colours of the editor, the scratchpad and the line-number gutter.
/// `NSColor` isn't `Sendable`, but these are immutable.
nonisolated struct EditorPalette: Equatable, @unchecked Sendable {
    let background: NSColor
    let text: NSColor
    let cursor: NSColor
    /// The selected text's background.
    let selection: NSColor
    /// The selected text's colour; `nil` keeps each token's colour.
    let selectedText: NSColor?
    /// Behind the line with the cursor; `nil` draws no highlight.
    let currentLine: NSColor?
    let gutterText: NSColor
    private let tokens: [TokenKind: TokenStyle]

    func style(for kind: TokenKind) -> TokenStyle {
        tokens[kind] ?? TokenStyle(color: nil)
    }

    /// The palette to draw with: Hyrule's variant follows the editor's appearance.
    static func palette(for setting: EditorThemeSetting, isDark: Bool) -> EditorPalette {
        switch setting {
        case .system: .system
        case .hyrule: isDark ? .hyruleDark : .hyruleLight
        }
    }

    /// System colours, which adapt to light and dark mode by themselves.
    static let system = EditorPalette(
        background: .textBackgroundColor,
        text: .textColor,
        cursor: .textColor,
        selection: .selectedTextBackgroundColor,
        selectedText: .selectedTextColor,
        currentLine: nil,
        gutterText: .secondaryLabelColor,
        tokens: [
            .heading: TokenStyle(color: .systemBlue, trait: .bold),
            .strong: TokenStyle(color: nil, trait: .bold),
            .emphasis: TokenStyle(color: nil, trait: .italic),
            .code: TokenStyle(color: .systemPink),
            .link: TokenStyle(color: .linkColor),
            .quote: TokenStyle(color: .secondaryLabelColor),
            .comment: TokenStyle(color: .secondaryLabelColor),
            .listMarker: TokenStyle(color: .systemOrange),
            .key: TokenStyle(color: .systemPurple),
            .string: TokenStyle(color: .systemRed),
            .number: TokenStyle(color: .systemBlue),
            .literal: TokenStyle(color: .systemPink),
            .punctuation: TokenStyle(color: .tertiaryLabelColor),
            .keyword: TokenStyle(color: .systemPink, trait: .bold),
        ]
    )

    /// Rainglow's Hyrule (hyrule.json) by Dayle Rees, MIT licensed.
    static let hyruleDark = hyrule(HyruleColors(
        background: "#2d2c2b", text: "#c0d5c1", gutter: "#615f5d", currentLine: "#353432",
        selection: "#569e1655", cursor: "#f8f8f0", green: "#569e16", yellow: "#f5c504", orange: "#ce830d",
        comment: "#716d6a", keyword: "#90c93f", number: "#f5c504"
    ))

    /// Rainglow's Hyrule Light (hyrule-light.json), with its three faintest colours darkened to be
    /// readable on its background: strings `#ce830d` → `#8f5a06` (1.97:1 → 3.72:1), comments
    /// `#93a594` → `#556856` (1.68:1 → 3.86:1) and numbers `#f5c504` → `#6b5500` (1.05:1 → 4.63:1).
    static let hyruleLight = hyrule(HyruleColors(
        background: "#c0d5c1", text: "#2d2c2b", gutter: "#83ac85", currentLine: "#b7cfb8",
        selection: "#569e1633", cursor: "#222222", green: "#407710", yellow: "#b7950c", orange: "#8f5a06",
        comment: "#556856", keyword: "#68912e", number: "#6b5500"
    ))

    /// One Hyrule variant, as hex; the names say which Rainglow scopes use each colour.
    private struct HyruleColors {
        let background, text, gutter, currentLine, selection, cursor: String
        /// Headings, JSON keys and `true`/`false`/`null`.
        let green: String
        /// Bold, italic and links.
        let yellow: String
        /// Strings and inline code.
        let orange: String
        let comment, keyword, number: String
    }

    private static func hyrule(_ hex: HyruleColors) -> EditorPalette {
        // The hex values are fixed above and covered by tests.
        func color(_ value: String) -> NSColor { HexColor(value)!.nsColor }
        let text = HexColor(hex.text)!
        return EditorPalette(
            background: color(hex.background),
            text: text.nsColor,
            cursor: color(hex.cursor),
            selection: color(hex.selection),
            selectedText: nil,
            currentLine: color(hex.currentLine),
            gutterText: color(hex.gutter),
            tokens: [
                .heading: TokenStyle(color: color(hex.green), trait: .bold),
                .strong: TokenStyle(color: color(hex.yellow), trait: .bold),
                .emphasis: TokenStyle(color: color(hex.yellow), trait: .italic),
                .code: TokenStyle(color: color(hex.orange)),
                .link: TokenStyle(color: color(hex.yellow)),
                .quote: TokenStyle(color: color(hex.comment)),
                .comment: TokenStyle(color: color(hex.comment)),
                .listMarker: TokenStyle(color: color(hex.keyword)),
                .key: TokenStyle(color: color(hex.green)),
                .string: TokenStyle(color: color(hex.orange)),
                .number: TokenStyle(color: color(hex.number)),
                .literal: TokenStyle(color: color(hex.green)),
                .punctuation: TokenStyle(color: text.withAlpha(0.6).nsColor),
                .keyword: TokenStyle(color: color(hex.keyword), trait: .bold),
            ]
        )
    }
}
