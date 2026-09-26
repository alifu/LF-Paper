//
//  QuickOpenPanel.swift
//  LF-Paper
//

import SwiftUI

/// File › Quick Open (⌘P): type part of a file name, ↑/↓ to choose, Return to open, Esc to close.
struct QuickOpenPanel: View {
    static let width: CGFloat = 560
    private static let rowHeight: CGFloat = 40
    private static let visibleRows: CGFloat = 9

    let model: WorkspaceModel
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var focusRequest = UUID()

    var body: some View {
        let results = model.quickOpenResults(for: query)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                PanelSearchField(
                    text: $query,
                    placeholder: "Open a file by name",
                    focusRequest: focusRequest,
                    onMove: { selectedIndex = Self.movedSelection(selectedIndex, by: $0, count: results.count) },
                    onSubmit: { openSelected(in: results) },
                    onCancel: { model.isQuickOpenPresented = false }
                )
                .accessibilityIdentifier("quick-open-field")
            }
            .padding(10)
            Divider()
            resultList(results)
        }
        .frame(width: Self.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .shadow(radius: 20, y: 8)
        .onChange(of: query) { selectedIndex = 0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick Open")
    }

    @ViewBuilder
    private func resultList(_ results: [QuickOpenResult]) -> some View {
        if results.isEmpty {
            Text(model.fileIndex.isEmpty ? "No Markdown or JSON files in this folder" : "No matching files")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: Self.rowHeight * 2)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            QuickOpenRow(result: result, isSelected: index == selectedIndex)
                                .frame(height: Self.rowHeight)
                                .contentShape(Rectangle())
                                .onTapGesture { model.open(result.file) }
                                .id(index)
                        }
                    }
                    .padding(6)
                }
                .frame(height: min(CGFloat(results.count), Self.visibleRows) * Self.rowHeight + 12)
                .onChange(of: selectedIndex) { _, index in proxy.scrollTo(index) }
            }
        }
    }

    private func openSelected(in results: [QuickOpenResult]) {
        guard results.indices.contains(selectedIndex) else { return }
        model.open(results[selectedIndex].file)
    }

    /// The row after moving `delta` rows, kept within the results.
    static func movedSelection(_ index: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index + delta, 0), count - 1)
    }
}

private struct QuickOpenRow: View {
    let result: QuickOpenResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: result.file.kind.systemImage)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(highlightedName)
                    .lineLimit(1)
                if !result.file.folderPath.isEmpty {
                    Text(result.file.folderPath)
                        .font(.caption)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(result.file.relativePath)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("quick-open-\(result.file.relativePath)")
    }

    /// The file name with the matched letters in bold.
    private var highlightedName: AttributedString {
        var name = AttributedString(result.file.name)
        let characters = Array(name.characters.indices)
        for offset in result.nameMatchOffsets where characters.indices.contains(offset) {
            let start = characters[offset]
            name[start..<name.characters.index(after: start)].font = .body.bold()
        }
        return name
    }
}
