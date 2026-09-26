//
//  CompareSourceCard.swift
//  LF-Paper
//

import SwiftUI

/// One side of the comparison: what's loaded, and buttons to open, paste or clear it.
struct CompareSourceCard: View {
    let label: String
    let source: CompareModel.Side?
    let onOpen: () -> Void
    let onPaste: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "curlybraces")
                    .foregroundStyle(.purple)
                    .accessibilityHidden(true)
                Text(source?.title ?? "Not set")
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let source {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(source.text.utf8.count), countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Open…", action: onOpen)
                Button("Paste", action: onPaste)
                if source != nil {
                    Button(action: onClear) {
                        Image(systemName: "xmark")
                    }
                    .help("Clear this side")
                    .accessibilityLabel("Clear \(label)")
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
