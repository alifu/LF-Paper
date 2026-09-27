//
//  SettingsView.swift
//  LF-Paper
//

import SwiftUI

/// LF-Paper › Settings… (⌘,).
struct SettingsView: View {
    @AppStorage(AppSettings.Key.appearance) private var appearance = AppAppearance.system
    @AppStorage(AppSettings.Key.editorFontSize) private var fontSize = AppSettings.defaultFontSize
    @AppStorage(AppSettings.Key.jsonIndentation) private var indentation = JSONIndentationSetting.twoSpaces
    @AppStorage(AppSettings.Key.autosaves) private var autosaves = false
    @AppStorage(AppSettings.Key.wrapsLines) private var wrapsLines = AppSettings.defaultWrapsLines
    @AppStorage(AppSettings.Key.editorTheme) private var editorTheme = EditorThemeSetting.system
    @AppStorage(AppSettings.Key.unsavedChangesOnClose) private var closeBehavior = UnsavedChangesOnClose.ask

    var body: some View {
        Form {
            Picker("Appearance:", selection: $appearance) {
                ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            LabeledContent("Editor font size:") {
                HStack {
                    Slider(value: $fontSize, in: AppSettings.fontSizeRange, step: AppSettings.fontSizeStep)
                        .frame(width: 160)
                        .accessibilityLabel("Editor font size")
                        .accessibilityValue("\(Int(fontSize)) points")
                    Text("\(Int(fontSize)) pt")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }

            Picker("Editor theme:", selection: $editorTheme) {
                ForEach(EditorThemeSetting.allCases) { Text($0.title).tag($0) }
            }
            .fixedSize()
            Caption("Hyrule (by Dayle Rees, from Rainglow) uses Hyrule Light in light mode.")

            Toggle("Wrap long lines (⌥⌘L)", isOn: $wrapsLines)
            Caption("When off, long lines scroll sideways. The scratchpad always wraps.")

            Picker("JSON indentation:", selection: $indentation) {
                ForEach(JSONIndentationSetting.allCases) { Text($0.title).tag($0) }
            }
            .fixedSize()

            Toggle("Save files automatically", isOn: $autosaves)
            Caption("Edits are saved a moment after you stop typing.")

            Picker("Closing a window:", selection: $closeBehavior) {
                ForEach(UnsavedChangesOnClose.allCases) { Text($0.title).tag($0) }
            }
            .fixedSize()
            Caption("What happens to unsaved changes when you close a window.")
        }
        .padding(20)
        .frame(width: 460)
    }
}

/// Help text under a setting. It wraps instead of widening the form, which would push the
/// labels past the window's edges.
private struct Caption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 260, alignment: .leading)
    }
}

#Preview {
    SettingsView()
}
