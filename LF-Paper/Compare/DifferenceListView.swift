//
//  DifferenceListView.swift
//  LF-Paper
//

import AppKit
import SwiftUI

/// Every structural difference with its path: changed, added or removed.
struct DifferenceListView: View {
    let differences: [JSONDifference]

    var body: some View {
        if differences.isEmpty {
            ContentUnavailableView(
                "No Structural Differences",
                systemImage: "checkmark.circle",
                description: Text("Both documents contain the same data.")
            )
        } else {
            List(differences.indices, id: \.self) { index in
                DifferenceRow(difference: differences[index])
            }
        }
    }
}

private struct DifferenceRow: View {
    /// Long values are cut here; Copy Value in the tree gives the full text.
    private static let detailLimit = 200

    let difference: JSONDifference

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .accessibilityLabel(label)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: difference.path.description)
                    .font(.body.monospaced())
                Text(verbatim: detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .contextMenu {
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(difference.path.description, forType: .string)
            }
        }
    }

    private var detail: String {
        let text = switch difference.kind {
        case .changed: "\(JSONDifference.text(of: difference.oldValue)) → \(JSONDifference.text(of: difference.newValue))"
        case .added: JSONDifference.text(of: difference.newValue)
        case .removed: JSONDifference.text(of: difference.oldValue)
        }
        return text.count > Self.detailLimit ? String(text.prefix(Self.detailLimit)) + "…" : text
    }

    private var symbol: String {
        switch difference.kind {
        case .added: "plus.circle.fill"
        case .removed: "minus.circle.fill"
        case .changed: "pencil.circle.fill"
        }
    }

    private var color: Color {
        switch difference.kind {
        case .added: .green
        case .removed: .red
        case .changed: .orange
        }
    }

    private var label: String {
        switch difference.kind {
        case .added: "Added"
        case .removed: "Removed"
        case .changed: "Changed"
        }
    }
}
