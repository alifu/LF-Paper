//
//  ReplacePreviewSheet.swift
//  LF-Paper
//

import SwiftUI

/// Shows every replacement Replace All would make before anything is written: each file with a
/// checkbox and its count, each change as its line before and after, and the files that will be skipped.
struct ReplacePreviewSheet: View {
    let model: WorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let plan = replace.plan {
                changes(in: plan)
                Divider()
                footer(for: plan)
            }
        }
        .frame(minWidth: 560, idealWidth: 680, minHeight: 360, idealHeight: 520)
    }

    private var replace: ReplaceSession { model.replace }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Replace All")
                .font(.headline)
            Text("“\(model.search.searchedText ?? "")” with “\(replace.replacement)”")
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(16)
    }

    private func changes(in plan: ReplacePlan) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(plan.files) { file in
                    Section {
                        ForEach(file.changes) { change in
                            ChangeRow(change: change)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                                .opacity(replace.isIncluded(file.id) ? 1 : 0.4)
                        }
                    } header: {
                        FileToggle(file: file, isIncluded: inclusion(of: file.id))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(.bar)
                    }
                }
                if !plan.skipped.isEmpty {
                    skippedFiles(plan.skipped)
                }
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func skippedFiles(_ skipped: [SkippedFile]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Skipped")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(skipped) { skipped in
                Label("\(skipped.file.relativePath): \(skipped.reason.description)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private func footer(for plan: ReplacePlan) -> some View {
        let replacements = plan.replacementCount(excluding: replace.excludedFiles)
        return HStack {
            Text(Self.summary(replacements: replacements, files: plan.fileCount(excluding: replace.excludedFiles)))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("replace-preview-summary")
            Spacer()
            Button("Cancel", role: .cancel) { replace.cancel() }
                .keyboardShortcut(.cancelAction)
            Button("Replace") { model.applyReplaceAll() }
                .keyboardShortcut(.defaultAction)
                .disabled(replacements == 0)
                .accessibilityIdentifier("replace-confirm-button")
        }
        .padding(16)
    }

    private func inclusion(of file: URL) -> Binding<Bool> {
        Binding(
            get: { replace.isIncluded(file) },
            set: { replace.setIncluded($0, file) }
        )
    }

    /// "12 replacements in 4 files", or "Nothing to replace" when every file is left out.
    static func summary(replacements: Int, files: Int) -> String {
        guard replacements > 0 else { return "Nothing to replace" }
        return "\(replacements) \(replacements == 1 ? "replacement" : "replacements") in \(files) \(files == 1 ? "file" : "files")"
    }
}

private struct FileToggle: View {
    let file: FileReplacement
    @Binding var isIncluded: Bool

    var body: some View {
        Toggle(isOn: $isIncluded) {
            HStack(spacing: 6) {
                Text(file.file.name)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(file.file.folderPath)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 4)
                Text("\(file.changes.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .accessibilityLabel("Replace in \(file.file.relativePath), \(file.changes.count) \(file.changes.count == 1 ? "change" : "changes")")
    }
}

/// One change: the line before (the match struck through in red) and after (the replacement in green).
private struct ChangeRow: View {
    let change: ReplaceChange

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(change.match.lineNumber)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.highlighted(change.match.preview, range: change.match.previewRange, color: .red, strikesThrough: true))
                Text(Self.highlighted(change.after.text, range: change.after.range, color: .green, strikesThrough: false))
            }
            .font(.system(.callout, design: .monospaced))
            .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Line \(change.match.lineNumber): \(change.match.preview), becomes \(change.after.text)")
    }

    private static func highlighted(_ line: String, range: NSRange, color: Color, strikesThrough: Bool) -> AttributedString {
        let text = line as NSString
        let before = text.substring(to: range.location)
        let changed = text.substring(with: range)
        let after = text.substring(from: NSMaxRange(range))
        var highlight = AttributedString(changed)
        highlight.backgroundColor = color.opacity(0.25)
        highlight.foregroundColor = .primary
        if strikesThrough { highlight.strikethroughStyle = .single }
        return AttributedString(before) + highlight + AttributedString(after)
    }
}
