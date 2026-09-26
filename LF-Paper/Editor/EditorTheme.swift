//
//  EditorTheme.swift
//  LF-Paper
//

import AppKit

/// Fonts and colors for the code editor. All colors are system colors, so they adapt to dark mode.
struct EditorTheme {
    static let standard = EditorTheme(fontSize: 13)

    let font: NSFont
    private let boldFont: NSFont
    private let italicFont: NSFont

    init(fontSize: CGFloat) {
        font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        boldFont = .monospacedSystemFont(ofSize: fontSize, weight: .bold)
        italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.textColor]
    }

    func attributes(for kind: TokenKind) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .heading: [.font: boldFont, .foregroundColor: NSColor.systemBlue]
        case .strong: [.font: boldFont]
        case .emphasis: [.font: italicFont]
        case .code: [.foregroundColor: NSColor.systemPink]
        case .link: [.foregroundColor: NSColor.linkColor]
        case .quote, .comment: [.foregroundColor: NSColor.secondaryLabelColor]
        case .listMarker: [.foregroundColor: NSColor.systemOrange]
        case .key: [.foregroundColor: NSColor.systemPurple]
        case .string: [.foregroundColor: NSColor.systemRed]
        case .number: [.foregroundColor: NSColor.systemBlue]
        case .literal: [.foregroundColor: NSColor.systemPink]
        case .punctuation: [.foregroundColor: NSColor.tertiaryLabelColor]
        }
    }
}
