//
//  JSONTreePane.swift
//  LF-Paper
//

import SwiftUI

/// The preview column for JSON files: a filterable tree. Selecting a value highlights it in the editor.
struct JSONTreePane: View {
    let model: WorkspaceModel
    @State private var query = ""
    @State private var visiblePaths: Set<JSONPath>?

    var body: some View {
        let session = model.json
        VStack(spacing: 0) {
            TextField("Filter keys and values", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(8)
            if case .invalid(let error) = session.status, session.tree != nil {
                StaleTreeBanner(error: error) { model.revealJSONError(error) }
            }
            content(for: session)
        }
        .onChange(of: query) { updateFilter() }
        .onChange(of: session.version) { updateFilter() }
    }

    @ViewBuilder
    private func content(for session: JSONSession) -> some View {
        if let tree = session.tree {
            JSONTreeView(
                root: tree,
                version: session.version,
                visiblePaths: visiblePaths,
                onSelect: { model.revealJSONValue(at: $0) }
            )
        } else if case .invalid(let error) = session.status {
            ContentUnavailableView {
                Label("Invalid JSON", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Show Error") { model.revealJSONError(error) }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func updateFilter() {
        visiblePaths = model.json.tree.flatMap { JSONTreeFilter.visiblePaths(in: $0.value, matching: query) }
    }
}

/// Shown above the tree while the text has an error: the tree is from the last valid version.
private struct StaleTreeBanner: View {
    let error: JSONParseError
    let onShowError: () -> Void

    var body: some View {
        HStack {
            Label("Showing the last valid version", systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .lineLimit(1)
            Spacer()
            Button("Show Error", action: onShowError)
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.yellow.opacity(0.15))
        .help(error.localizedDescription)
    }
}
