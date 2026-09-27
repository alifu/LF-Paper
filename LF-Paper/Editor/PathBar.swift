//
//  PathBar.swift
//  LF-Paper
//

import SwiftUI

/// Where the open file is, above the editor: the folder, each folder below it, then the file.
/// Clicking a part shows it in the sidebar; right-clicking copies its path or reveals it in Finder.
/// When the path doesn't fit, the folders after the first are replaced by "…", from the front,
/// so the file and the folders nearest it stay readable.
struct PathBar: View {
    /// The widest a folder name is drawn; the open folder's (first) name gets a little less.
    private static let folderWidth: CGFloat = 180
    private static let firstFolderWidth: CGFloat = 160

    let model: WorkspaceModel

    var body: some View {
        let segments = model.pathSegments
        ViewThatFits(in: .horizontal) {
            ForEach(0..<max(segments.count - 1, 1), id: \.self) { hidden in
                row(Self.shortened(segments, hiding: hidden))
            }
            // Nothing else fits: the file name alone, truncated if need be.
            row(segments.suffix(1).map { .segment($0) })
        }
        .font(.callout)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Path: \(segments.map(\.name).joined(separator: ", "))")
        .accessibilityIdentifier("path-bar")
    }

    nonisolated enum Part: Identifiable {
        case segment(PathSegment)
        /// Folders left out for space.
        case ellipsis

        var id: String {
            switch self {
            case .segment(let segment): segment.url.absoluteString
            case .ellipsis: "…"
            }
        }
    }

    /// The first part, "…" in place of the `hidden` parts after it, then the rest.
    nonisolated static func shortened(_ segments: [PathSegment], hiding hidden: Int) -> [Part] {
        guard hidden > 0, segments.count > hidden + 1 else { return segments.map { .segment($0) } }
        return [.segment(segments[0]), .ellipsis] + segments.dropFirst(hidden + 1).map { .segment($0) }
    }

    private func row(_ parts: [Part]) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                if index > 0 {
                    Image(systemName: "chevron.compact.right")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                switch part {
                case .segment(let segment):
                    SegmentButton(segment: segment, model: model)
                        // A long folder name is shortened in the middle rather than crowding out the rest.
                        .frame(maxWidth: segment.isFolder ? (index == 0 ? Self.firstFolderWidth : Self.folderWidth) : nil, alignment: .leading)
                case .ellipsis:
                    Text("…")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .fixedSize(horizontal: parts.count > 1, vertical: false) // a row of several parts fits whole or not at all
    }
}

private struct SegmentButton: View {
    let segment: PathSegment
    let model: WorkspaceModel

    var body: some View {
        Button {
            if segment.isInWorkspace { model.showInSidebar(segment.url) }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: segment.isFolder ? "folder" : fileIcon)
                    .foregroundStyle(.secondary)
                Text(segment.name)
                    .truncationMode(.middle)
                    .foregroundStyle(segment.isFolder ? .secondary : .primary)
            }
        }
        .buttonStyle(.plain)
        .help(segment.isInWorkspace ? "Show in Sidebar" : segment.url.path(percentEncoded: false))
        .contextMenu { menu }
        .accessibilityLabel(segment.name)
        .accessibilityIdentifier("path-segment-\(segment.name)")
    }

    private var fileIcon: String {
        FileKind(fileExtension: segment.url.pathExtension)?.systemImage ?? "doc"
    }

    @ViewBuilder
    private var menu: some View {
        Button("Copy Path") { model.copyPath(of: segment.url, relative: false) }
        if FilePath.relativePath(of: segment.url, root: model.rootURL) != nil {
            Button("Copy Relative Path") { model.copyPath(of: segment.url, relative: true) }
        }
        Divider()
        Button("Reveal in Finder") { model.revealInFinder(segment.url) }
        if segment.isInWorkspace {
            Button("Show in Sidebar") { model.showInSidebar(segment.url) }
        }
    }
}
