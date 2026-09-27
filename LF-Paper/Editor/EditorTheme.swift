//
//  EditorTheme.swift
//  LF-Paper
//

import AppKit

/// Fonts and colours for the code editor: a font size and an `EditorPalette`.
struct EditorTheme {
    static let defaultFontSize = CGFloat(AppSettings.defaultFontSize)
    static let standard = EditorTheme(fontSize: defaultFontSize)

    let font: NSFont
    let palette: EditorPalette
    private let boldFont: NSFont
    private let italicFont: NSFont

    init(fontSize: CGFloat, palette: EditorPalette = .system) {
        font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        boldFont = .monospacedSystemFont(ofSize: fontSize, weight: .bold)
        italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        self.palette = palette
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: palette.text]
    }

    func attributes(for kind: TokenKind) -> [NSAttributedString.Key: Any] {
        let style = palette.style(for: kind)
        var attributes: [NSAttributedString.Key: Any] = [:]
        switch style.trait {
        case .regular: break
        case .bold: attributes[.font] = boldFont
        case .italic: attributes[.font] = italicFont
        }
        if let color = style.color {
            attributes[.foregroundColor] = color
        }
        return attributes
    }
}
