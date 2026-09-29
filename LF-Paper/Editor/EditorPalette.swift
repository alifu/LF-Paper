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

    /// `nil` if the colour can't be expressed in sRGB.
    init?(_ color: NSColor) {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        self.init(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent, alpha: srgb.alphaComponent)
    }

    /// `#rrggbb`, or `#rrggbbaa` when not opaque.
    var hexString: String {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        let opaque = String(format: "#%02x%02x%02x", byte(red), byte(green), byte(blue))
        return alpha >= 1 ? opaque : opaque + String(format: "%02x", byte(alpha))
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
    /// Rainglow's GitHub, with GitHub Light in light mode.
    case github
    /// Rainglow's Hyrule, with Hyrule Light in light mode.
    case hyrule
    /// The user's own colours, from Settings › Edit Custom Theme.
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .github: "GitHub"
        case .hyrule: "Hyrule"
        case .custom: "Custom"
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
    let tokens: [TokenKind: TokenStyle]

    func style(for kind: TokenKind) -> TokenStyle {
        tokens[kind] ?? TokenStyle(color: nil)
    }

    /// The palette to draw with: a theme's light or dark variant follows the editor's appearance.
    static func palette(
        for setting: EditorThemeSetting,
        isDark: Bool,
        customTheme: CustomTheme = .standard
    ) -> EditorPalette {
        switch setting {
        case .system: .system
        case .github: isDark ? .githubDark : .githubLight
        case .hyrule: isDark ? .hyruleDark : .hyruleLight
        case .custom: EditorPalette(colors: isDark ? customTheme.dark : customTheme.light) ?? (isDark ? .githubDark : .githubLight)
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
}
