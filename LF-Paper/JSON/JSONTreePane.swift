//
//  JSONTreePane.swift
//  LF-Paper
//

import SwiftUI

/// The preview column for JSON files: a tree filtered by text or by a JSONPath query (text starting
/// with `$`, such as `$.users[?(@.active)].name`). Selecting a value highlights it in the editor.
struct JSONTreePane: View {
    let model: WorkspaceModel
    @State private var query = ""
    @State private var search = JSONTreeSearch.Result.everything

    var body: some View {
        let session = model.json
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Filter, or a JSONPath query such as $..name", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("json-query-field")
                searchStatus
            }
            .padding(8)
            if case .invalid(let error) = session.status, session.tree != nil {
                StaleTreeBanner(error: error) { model.revealJSONError(error) }
            }
            content(for: session)
            SchemaPanel(model: model)
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
                visiblePaths: search.visiblePaths,
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

    @ViewBuilder
    private var searchStatus: some View {
        if let error = search.error {
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityIdentifier("json-query-status")
        } else if let count = search.matchCount {
            Text(count == 1 ? "1 match" : "\(count) matches")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("json-query-status")
        }
    }

    private func updateFilter() {
        search = model.json.tree.map { JSONTreeSearch.result(for: query, in: $0.value) } ?? .everything
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
