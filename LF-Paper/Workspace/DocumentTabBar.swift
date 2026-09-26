//
//  DocumentTabBar.swift
//  LF-Paper
//

import SwiftUI

/// The pinned Scratch tab, then a row of tabs for the open files: click to switch, × (or ⌘W) to close.
/// A dot marks unsaved changes.
struct DocumentTabBar: View {
    let model: WorkspaceModel

    var body: some View {
        HStack(spacing: 0) {
            DocumentTab(
                name: "Scratch",
                systemImage: "square.and.pencil",
                isActive: model.isScratchpadActive,
                hasUnsavedChanges: false,
                onSelect: { model.showScratchpad() },
                onClose: nil,
                tooltip: "Scratchpad: never saved (⇧⌘E)"
            )
            .fixedSize(horizontal: true, vertical: false) // pinned: only as wide as its label
            Divider()
            fileTabs
        }
        .frame(height: DocumentTab.height)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open files")
    }

    private var fileTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(model.tabs) { document in
                        DocumentTab(
                            name: document.url.lastPathComponent,
                            systemImage: FileKind(fileExtension: document.url.pathExtension)?.systemImage ?? "doc",
                            isActive: document.id == model.document?.id,
                            hasUnsavedChanges: model.hasUnsavedChanges(inTab: document.id),
                            onSelect: { model.activateTab(document.id) },
                            onClose: { model.closeTab(document.id) }
                        )
                        .id(document.id)
                        Divider()
                    }
                }
            }
            .onChange(of: model.document?.id) { _, id in
                if let id { withAnimation { proxy.scrollTo(id) } }
            }
        }
    }
}

private struct DocumentTab: View {
    static let height: CGFloat = 30

    let name: String
    let systemImage: String
    let isActive: Bool
    let hasUnsavedChanges: Bool
    let onSelect: () -> Void
    /// `nil` for a tab that can't be closed (the Scratch tab).
    let onClose: (() -> Void)?
    var tooltip: String?

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
            if let onClose {
                closeButton(onClose)
            }
        }
        .font(.callout)
        .padding(.leading, 10)
        .padding(.trailing, onClose == nil ? 10 : 6)
        .frame(maxWidth: 220, maxHeight: .infinity)
        .background(isActive ? AnyShapeStyle(.background) : AnyShapeStyle(.clear))
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle().fill(.tint).frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasUnsavedChanges ? "\(name), edited" : name)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, onSelect)
        .accessibilityActions {
            if let onClose {
                Button("Close", action: onClose)
            }
        }
        .accessibilityIdentifier("tab-\(name)")
        .help(tooltip ?? name)
    }

    /// A dot for unsaved changes that turns into × on hover, like Xcode and Safari.
    private func closeButton(_ onClose: @escaping () -> Void) -> some View {
        Button(action: onClose) {
            Image(systemName: hasUnsavedChanges && !isHovering ? "circle.fill" : "xmark")
                .font(.system(size: hasUnsavedChanges && !isHovering ? 7 : 9, weight: .semibold))
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .opacity(isActive || isHovering || hasUnsavedChanges ? 1 : 0)
        .help("Close Tab (⌘W)")
    }
}
