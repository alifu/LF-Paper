//
//  SchemaPanel.swift
//  LF-Paper
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Under the JSON tree: which schema the file is checked against, and its problems.
/// Clicking a problem selects it in the editor.
struct SchemaPanel: View {
    private static let listHeight: CGFloat = 140

    let model: WorkspaceModel

    var body: some View {
        if let document = model.document, model.isJSONDocument {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                header(documentURL: document.url)
                if case .checked(_, let issues) = model.schema.state, !issues.isEmpty {
                    issueList(issues)
                }
            }
            .task(id: CheckTrigger(version: model.json.version, choice: model.schema.choice(for: document.url), documentID: document.id)) {
                await model.checkSchema()
            }
        }
    }

    /// Re-check after each successful parse, a new schema choice, or another file.
    private struct CheckTrigger: Equatable {
        let version: Int
        let choice: SchemaChoice
        let documentID: UUID
    }

    private func header(documentURL: URL) -> some View {
        HStack(spacing: 6) {
            Image(systemName: statusSymbol.name)
                .foregroundStyle(statusSymbol.color)
                .accessibilityHidden(true)
            Text(statusText)
                .lineLimit(2)
                .accessibilityIdentifier("schema-status")
            Spacer(minLength: 4)
            Menu("Schema") {
                Button("Use the File’s $schema") { model.schema.setChoice(.automatic, for: documentURL) }
                Button("Choose Schema File…") { chooseSchema(for: documentURL) }
                Divider()
                Button("Don’t Check") { model.schema.setChoice(.off, for: documentURL) }
            }
            .fixedSize()
        }
        .font(.callout)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func issueList(_ issues: [SchemaIssue]) -> some View {
        List(issues) { issue in
            Button {
                model.reveal(issue)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(issue.line.map { "Line \($0)" } ?? "—")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 52, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(issue.message)
                        Text(issue.path.description)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Line \(issue.line.map(String.init) ?? "unknown"), \(issue.path.description): \(issue.message)")
        }
        .listStyle(.plain)
        .frame(height: Self.listHeight)
    }

    private var statusText: String {
        switch model.schema.state {
        case .none:
            "No schema. Add \"$schema\" with a file path, or choose one."
        case .off:
            "Schema checks are off for this file."
        case .remote(let address):
            "\(address) is on the web; schemas aren’t downloaded. Choose a local file."
        case .unreadable(let name, let reason):
            "\(name): \(reason)"
        case .checked(let name, let issues):
            issues.isEmpty
                ? "Matches \(name)"
                : "\(issues.count) \(issues.count == 1 ? "problem" : "problems") with \(name)"
        }
    }

    private var statusSymbol: (name: String, color: Color) {
        switch model.schema.state {
        case .none, .off, .remote: ("doc.badge.gearshape", .secondary)
        case .unreadable: ("exclamationmark.triangle.fill", .orange)
        case .checked(_, let issues): issues.isEmpty ? ("checkmark.seal.fill", .green) : ("xmark.seal.fill", .red)
        }
    }

    private func chooseSchema(for documentURL: URL) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.directoryURL = documentURL.deletingLastPathComponent()
        panel.message = "Choose a JSON Schema file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.schema.setChoice(.file(url), for: documentURL)
    }
}
