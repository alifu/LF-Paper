//
//  AppSettings.swift
//  LF-Paper
//

import AppKit

/// Settings keys, defaults and limits. Views read and write them with `@AppStorage`.
nonisolated enum AppSettings {
    enum Key {
        static let appearance = "settings.appearance"
        static let editorFontSize = "settings.editorFontSize"
        static let jsonIndentation = "settings.jsonIndentation"
        static let autosaves = "settings.autosaves"
    }

    enum Zoom {
        case bigger
        case smaller
        case actualSize
    }

    static let defaultFontSize = 13.0
    static let fontSizeRange: ClosedRange<Double> = 9...32
    static let fontSizeStep = 1.0
    /// How long after typing stops an autosave happens.
    static let autosaveDelay: Duration = .seconds(1)

    static func clampedFontSize(_ size: Double) -> Double {
        min(max(size, fontSizeRange.lowerBound), fontSizeRange.upperBound)
    }

    /// The font size after View › Bigger, Smaller or Actual Size.
    static func fontSize(_ size: Double, zoomed zoom: Zoom) -> Double {
        switch zoom {
        case .bigger: clampedFontSize(size + fontSizeStep)
        case .smaller: clampedFontSize(size - fontSizeStep)
        case .actualSize: defaultFontSize
        }
    }
}

/// Light, dark, or following the system.
nonisolated enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` follows the system setting.
    var appearanceName: NSAppearance.Name? {
        switch self {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
}

/// How Format indents JSON.
nonisolated enum JSONIndentationSetting: String, CaseIterable, Identifiable {
    case twoSpaces
    case fourSpaces
    case tab

    var id: Self { self }

    var title: String {
        switch self {
        case .twoSpaces: "2 Spaces"
        case .fourSpaces: "4 Spaces"
        case .tab: "Tab"
        }
    }

    var indentation: JSONFormatter.Indentation {
        switch self {
        case .twoSpaces: .spaces(2)
        case .fourSpaces: .spaces(4)
        case .tab: .tab
        }
    }
}
