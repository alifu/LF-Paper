//
//  ScratchpadBar.swift
//  LF-Paper
//

import SwiftUI

/// Above the scratchpad editor: live counts, Copy All and Clear.
struct ScratchpadBar: View {
    /// How long "Copied" stays after copying.
    private static let copiedFeedbackDuration: Duration = .seconds(1.5)

    let model: WorkspaceModel
    @State private var isShowingCopied = false

    var body: some View {
        HStack(spacing: 12) {
            Text(Self.countsDescription(ScratchpadStats(text: model.scratchpadText)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("scratchpad-counts")
            Spacer()
            if isShowingCopied {
                Label("Copied", systemImage: "checkmark")
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Button("Copy All", systemImage: "doc.on.doc") { model.copyScratchpad() }
                .disabled(model.scratchpadText.isEmpty)
                .help("Copy the whole scratchpad as plain text (⌥⇧⌘C)")
            Button("Clear", systemImage: "trash") { model.clearScratchpad() }
                .disabled(model.scratchpadText.isEmpty)
                .help("Empty the scratchpad (⌘Z brings the text back)")
        }
        .font(.callout)
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(.bar)
        .task(id: model.scratchpadCopyID) {
            guard model.scratchpadCopyID != nil else { return }
            withAnimation { isShowingCopied = true }
            try? await Task.sleep(for: Self.copiedFeedbackDuration) // a cancelled sleep ends early; checked below
            guard !Task.isCancelled else { return }
            withAnimation { isShowingCopied = false }
        }
    }

    static func countsDescription(_ stats: ScratchpadStats) -> String {
        [
            counted(stats.characters, "character"),
            counted(stats.words, "word"),
            counted(stats.lines, "line"),
        ].joined(separator: " · ")
    }

    private static func counted(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}
