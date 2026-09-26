//
//  ReadOnlyDocumentView.swift
//  LF-Paper
//

import SwiftUI

/// Temporary read-only view of the open file. The Phase 2 editor replaces it.
struct ReadOnlyDocumentView: View {
    /// SwiftUI `Text` gets slow on very large strings; the real editor has no such limit.
    private static let displayLimit = 200_000

    let document: OpenDocument?

    var body: some View {
        if let document {
            ScrollView {
                Text(verbatim: String(document.text.prefix(Self.displayLimit)))
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding()
            }
        } else {
            ContentUnavailableView(
                "No File Selected",
                systemImage: "doc.text",
                description: Text("Select a Markdown or JSON file in the sidebar.")
            )
        }
    }
}
