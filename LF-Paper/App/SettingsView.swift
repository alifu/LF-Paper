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

            Picker("JSON indentation:", selection: $indentation) {
                ForEach(JSONIndentationSetting.allCases) { Text($0.title).tag($0) }
            }
            .fixedSize()

            Toggle("Save files automatically", isOn: $autosaves)
            Text("Edits are saved a moment after you stop typing.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Closing a window:", selection: $closeBehavior) {
                ForEach(UnsavedChangesOnClose.allCases) { Text($0.title).tag($0) }
            }
            .fixedSize()
            Text("What happens to unsaved changes when you close a window.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 420)
    }
}

#Preview {
    SettingsView()
}
