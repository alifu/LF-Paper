//
//  OutlineView.swift
//  LF-Paper
//

import SwiftUI

/// The sidebar's Outline mode: the headings of the Markdown file being edited, indented by level.
/// Choosing one moves the editor and the preview there.
struct OutlineView: View {
    private static let indentPerLevel: CGFloat = 12

    let model: WorkspaceModel

    var body: some View {
        if let document = model.document, model.isMarkdownDocument {
            content(model.outline.headings(for: document.id))
                .task(id: document.text) {
                    await model.outline.refresh(document.text, documentID: document.id)
                }
        } else {
            ContentUnavailableView(
                "No Outline",
                systemImage: "list.bullet.indent",
                description: Text("Open a Markdown file to see its headings.")
            )
        }
    }

    @ViewBuilder
    private func content(_ headings: [MarkdownHeading]?) -> some View {
        if let headings, headings.isEmpty {
            ContentUnavailableView("No Headings", systemImage: "list.bullet.indent", description: Text("Headings start with #."))
        } else if let headings {
            List(headings) { heading in
                Button {
                    model.show(heading)
                } label: {
                    Text(heading.title.isEmpty ? "Untitled" : heading.title)
                        .fontWeight(heading.level <= 2 ? .semibold : .regular)
                        .lineLimit(1)
                        .padding(.leading, CGFloat(heading.level - 1) * Self.indentPerLevel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Heading level \(heading.level): \(heading.title)")
                .help("Line \(heading.line)")
            }
            .listStyle(.sidebar)
        } else {
            Color.clear // still reading the headings
        }
    }
}
