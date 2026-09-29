//
//  ThemeEditorView.swift
//  LF-Paper
//

import SwiftUI

/// Settings › Edit Custom Theme…: a colour well for each colour of the editor, for light and dark mode.
/// Changes are saved as they're made, so the open editor updates live.
struct ThemeEditorView: View {
    private enum Variant: String, CaseIterable, Identifiable {
        case light = "Light"
        case dark = "Dark"

        var id: Self { self }
    }

    private struct Slot: Identifiable {
        let title: String
        let keyPath: WritableKeyPath<ThemeColors, String>
        var supportsOpacity = false

        var id: String { title }
    }

    private static let slots = [
        Slot(title: "Background", keyPath: \.background),
        Slot(title: "Text", keyPath: \.text),
        Slot(title: "Cursor", keyPath: \.cursor),
        Slot(title: "Selection", keyPath: \.selection, supportsOpacity: true),
        Slot(title: "Current line", keyPath: \.currentLine),
        Slot(title: "Line numbers", keyPath: \.gutter),
        Slot(title: "Headings and keys", keyPath: \.heading),
        Slot(title: "Bold, italic and links", keyPath: \.emphasis),
        Slot(title: "Strings and code", keyPath: \.string),
        Slot(title: "Numbers", keyPath: \.number),
        Slot(title: "Keywords and bullets", keyPath: \.keyword),
        Slot(title: "Comments", keyPath: \.comment),
    ]

    @AppStorage(AppSettings.Key.customTheme) private var customThemeJSON = ""
    @State private var variant = Variant.light
    @Environment(\.dismiss) private var dismiss

    private var theme: CustomTheme { CustomTheme(json: customThemeJSON) ?? .standard }

    private var colors: ThemeColors {
        variant == .light ? theme.light : theme.dark
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Variant:", selection: $variant) {
                ForEach(Variant.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Form {
                ForEach(Self.slots) { slot in
                    ColorPicker(slot.title, selection: binding(for: slot), supportsOpacity: slot.supportsOpacity)
                }
            }

            preview

            HStack {
                Button("Reset to GitHub") { customThemeJSON = CustomTheme.standard.json }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    /// A few lines in the theme's colours, with the text's contrast against the background.
    private var preview: some View {
        let colors = colors
        func color(_ hex: String) -> Color { HexColor(hex).map { Color(nsColor: $0.nsColor) } ?? .clear }
        return VStack(alignment: .leading, spacing: 4) {
            Text(sampleLine(colors))
            Text("# a comment").foregroundColor(color(colors.comment))
            if let ratio = contrastOfText(in: colors) {
                Text("Text contrast \(ratio.formatted(.number.precision(.fractionLength(1)))):1")
                    .font(.caption)
                    .foregroundColor(color(colors.gutter))
            }
        }
        .font(.system(.body, design: .monospaced))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color(colors.background), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the \(variant.rawValue.lowercased()) theme")
    }

    private func sampleLine(_ colors: ThemeColors) -> AttributedString {
        let parts = [("{ ", colors.text), ("\"name\"", colors.heading), (": ", colors.text), ("\"Ada\"", colors.string),
                     (", ", colors.text), ("\"count\"", colors.heading), (": ", colors.text), ("42", colors.number),
                     (" }", colors.text)]
        return parts.reduce(into: AttributedString()) { line, part in
            var piece = AttributedString(part.0)
            piece.foregroundColor = HexColor(part.1)?.nsColor
            line += piece
        }
    }

    private func contrastOfText(in colors: ThemeColors) -> Double? {
        guard let text = HexColor(colors.text), let background = HexColor(colors.background) else { return nil }
        return HexColor.contrastRatio(text, background)
    }

    private func binding(for slot: Slot) -> Binding<Color> {
        Binding(
            get: { HexColor(colors[keyPath: slot.keyPath]).map { Color(nsColor: $0.nsColor) } ?? .clear },
            set: { newColor in
                guard let hex = HexColor(NSColor(newColor))?.hexString else { return }
                update { $0[keyPath: slot.keyPath] = hex }
            }
        )
    }

    /// Saves a copy of the theme with the current variant changed.
    private func update(_ change: (inout ThemeColors) -> Void) {
        var updated = theme
        switch variant {
        case .light: change(&updated.light)
        case .dark: change(&updated.dark)
        }
        customThemeJSON = updated.json
    }
}

#Preview {
    ThemeEditorView()
}
