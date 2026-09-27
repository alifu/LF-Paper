//
//  SwiftModelSheet.swift
//  LF-Paper
//

import SwiftUI

/// JSON › Generate Swift Model…: the options on the left, the code they make on the right.
/// Open in New Tab puts the code in an unsaved tab; nothing is written until it's saved.
struct SwiftModelSheet: View {
    let model: WorkspaceModel
    @Bindable var session: SwiftModelSession

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                options
                    .frame(width: 280)
                Divider()
                preview
            }
            Divider()
            footer
        }
        .frame(minWidth: 820, idealWidth: 920, minHeight: 520, idealHeight: 620)
    }

    private var options: some View {
        Form {
            Section {
                Picker("Kind", selection: $session.options.kind) {
                    ForEach(SwiftModelOptions.Kind.allCases) { Text($0.title).tag($0) }
                }
                TextField("Root type", text: $session.options.rootName)
                    .accessibilityIdentifier("swift-model-root-name")
            }
            Section {
                Picker("Properties", selection: $session.options.usesVar) {
                    Text("let").tag(false)
                    Text("var").tag(true)
                }
                .pickerStyle(.segmented)
                Picker("Access", selection: $session.options.isPublic) {
                    Text("internal").tag(false)
                    Text("public").tag(true)
                }
                .pickerStyle(.segmented)
                Picker("Names", selection: $session.options.keyStyle) {
                    ForEach(SwiftModelOptions.KeyStyle.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Conformances") {
                ForEach(SwiftModelOptions.Conformance.allCases) { conformance in
                    Toggle(conformance.rawValue, isOn: isChosen(conformance))
                        .disabled(!session.options.allows(conformance))
                        .help(help(for: conformance))
                }
            }
            Section("Detect") {
                Toggle("ISO 8601 dates as Date", isOn: $session.options.detectsDates)
                Toggle("Web addresses as URL", isOn: $session.options.detectsURLs)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var preview: some View {
        if let source = session.source {
            ScrollView([.vertical, .horizontal]) {
                Text(source)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize()
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .accessibilityIdentifier("swift-model-preview")
        } else {
            ContentUnavailableView(
                "No Model",
                systemImage: "exclamationmark.triangle",
                description: Text(session.error?.localizedDescription ?? "")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            Text(session.source == nil ? "" : "Opens as \(session.fileName), not saved yet")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel", role: .cancel) { model.swiftModelGenerator = nil }
                .keyboardShortcut(.cancelAction)
            Button("Open in New Tab") { model.openGeneratedSwiftModel() }
                .keyboardShortcut(.defaultAction)
                .disabled(session.source == nil)
                .accessibilityIdentifier("swift-model-open-button")
        }
        .padding(16)
    }

    private func isChosen(_ conformance: SwiftModelOptions.Conformance) -> Binding<Bool> {
        Binding(
            get: { session.options.conformances.contains(conformance) && session.options.allows(conformance) },
            set: { isOn in
                if isOn {
                    session.options.conformances.insert(conformance)
                } else {
                    session.options.conformances.remove(conformance)
                }
            }
        )
    }

    private func help(for conformance: SwiftModelOptions.Conformance) -> String {
        switch conformance {
        case .identifiable: "Added to types that have an id"
        case .sendable where session.options.kind == .classes: "Needs let properties"
        case _ where session.options.kind == .dictionary: "Not available: dictionary-based models hold Any"
        default: ""
        }
    }
}
