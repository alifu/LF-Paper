//
//  CompareView.swift
//  LF-Paper
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Compare window: two sources, options, and the differences side by side or as a list.
/// Plain text (such as a Markdown file against its saved version) has only the side-by-side view.
struct CompareView: View {
    static let windowID = "compare-json"

    private enum Mode: String, CaseIterable, Identifiable {
        case sideBySide = "Side by Side"
        case changes = "Changes"
        var id: Self { self }
    }

    @Bindable var model: CompareModel
    @State private var mode: Mode = .sideBySide
    @State private var isImporting = false
    @State private var importSide: JSONComparison.Side = .left

    var body: some View {
        VStack(spacing: 0) {
            sources
            Divider()
            optionsBar
            Divider()
            results
                // The empty and invalid messages don't fill the space on their own, which would
                // center the whole column and leave a gap above the source cards.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 440)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): model.loadSide(importSide, from: url)
            case .failure: break // cancelled or unavailable; nothing to load
            }
        }
        .alert(isPresented: isShowingError, error: model.presentedError) { _ in
            Button("OK") {}
        } message: { error in
            Text(error.recoverySuggestion ?? "")
        }
    }

    // MARK: Sources

    private var sources: some View {
        HStack(alignment: .center, spacing: 8) {
            card(for: .left, label: "Left (old)")
            Button {
                model.swapSides()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .help("Swap sides")
            .accessibilityLabel("Swap Sides")
            card(for: .right, label: "Right (new)")
        }
        .padding(10)
    }

    private func card(for side: JSONComparison.Side, label: String) -> some View {
        CompareSourceCard(
            label: label,
            source: side == .left ? model.left : model.right,
            onOpen: {
                importSide = side
                isImporting = true
            },
            onPaste: { paste(into: side) },
            onClear: { model.clearSide(side) }
        )
    }

    private func paste(into side: JSONComparison.Side) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        model.setSide(side, title: "Pasted", text: text)
    }

    // MARK: Options

    private var optionsBar: some View {
        HStack(spacing: 12) {
            if model.contentKind == .json {
                Toggle("Ignore key order", isOn: $model.ignoresKeyOrder)
                TextField("Match array items by key (e.g. id)", text: $model.arrayMatchKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
            } else {
                Text("Comparing text line by line")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.contentKind == .json {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            navigation
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var navigation: some View {
        HStack(spacing: 4) {
            Button {
                model.focusPreviousChange()
            } label: {
                Image(systemName: "chevron.up")
            }
            .accessibilityLabel("Previous Change")
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .help("Previous change (⌥⌘↑)")
            Text(changeCounter)
                .monospacedDigit()
                .accessibilityIdentifier("change-counter")
                .foregroundStyle(.secondary)
                .frame(minWidth: 80)
            Button {
                model.focusNextChange()
            } label: {
                Image(systemName: "chevron.down")
            }
            .accessibilityLabel("Next Change")
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .help("Next change (⌥⌘↓)")
        }
        .disabled(model.changeCount == 0 || visibleMode != .sideBySide)
    }

    private var changeCounter: String {
        switch (model.focusedChange, model.changeCount) {
        case (_, 0): model.result == nil ? "" : "No changes"
        case (let focused?, let count): "\(focused + 1) of \(count)"
        case (nil, let count): count == 1 ? "1 change" : "\(count) changes"
        }
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        switch model.outcome {
        case .incomplete:
            ContentUnavailableView(
                "Choose Two JSON Documents",
                systemImage: "square.split.2x1",
                description: Text("Open or paste JSON on both sides, or right-click JSON files in the sidebar and choose Compare as Left or Compare as Right.")
            )
        case .invalid(let side, let error):
            ContentUnavailableView {
                Label("The \(side == .left ? "left" : "right") side isn’t valid JSON", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.localizedDescription)
            }
        case .compared(let result):
            switch visibleMode {
            case .sideBySide:
                SideBySideDiffView(
                    rows: result.rows,
                    changeStarts: result.changeStarts,
                    focusedChange: model.focusedChange,
                    longestLines: result.longestLines
                )
            case .changes:
                DifferenceListView(differences: result.differences)
            }
        }
    }

    /// Plain text has no structural list, so it's always side by side.
    private var visibleMode: Mode {
        model.contentKind == .json ? mode : .sideBySide
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { model.presentedError != nil },
            set: { isPresented in
                if !isPresented { model.presentedError = nil }
            }
        )
    }
}
