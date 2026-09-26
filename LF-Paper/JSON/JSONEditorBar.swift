//
//  JSONEditorBar.swift
//  LF-Paper
//

import SwiftUI

/// Above the JSON editor: live validation (click an error to jump to it), Format and Minify.
struct JSONEditorBar: View {
    let model: WorkspaceModel

    var body: some View {
        HStack(spacing: 8) {
            status
            Spacer(minLength: 8)
            Menu("Format") {
                Button("2 Spaces") { model.formatJSON(indentation: .spaces(2)) }
                Button("4 Spaces") { model.formatJSON(indentation: .spaces(4)) }
                Button("Tabs") { model.formatJSON(indentation: .tab) }
                Divider()
                Button("Sort Keys") { model.formatJSON(sortsKeys: true) }
            } primaryAction: {
                model.formatJSON()
            }
            .fixedSize()
            .help("Pretty-print (⌥⇧F). Click the arrow for indentation and key sorting.")
            Button("Minify") { model.minifyJSON() }
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    @ViewBuilder
    private var status: some View {
        switch model.json.status {
        case .valid:
            Label("Valid JSON", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .invalid(let error):
            Button {
                model.revealJSONError(error)
            } label: {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.orange)
            .help("Show the error in the editor")
        case .analyzing, .inactive:
            Label("Checking…", systemImage: "clock")
                .foregroundStyle(.secondary)
        }
    }
}
