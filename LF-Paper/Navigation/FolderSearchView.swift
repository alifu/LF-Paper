//
//  FolderSearchView.swift
//  LF-Paper
//

import SwiftUI

/// The sidebar's Search mode (⇧⌘F): a query with options, an optional Replace field (⌥⇧⌘F),
/// then matches grouped by file. Return searches, Esc stops a running search; clicking a match
/// opens it and selects the text. Replace All… (or Return in the Replace field) opens a preview.
struct FolderSearchView: View {
    let model: WorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            results
        }
    }

    private var searchBar: some View {
        @Bindable var search = model.search
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                replaceDisclosure
                PanelSearchField(
                    text: $search.text,
                    placeholder: "Search in folder",
                    focusRequest: model.searchFocusRequest,
                    onSubmit: { model.runFolderSearch() },
                    onCancel: { search.cancel() }
                )
                .accessibilityIdentifier("folder-search-field")
            }
            if replace.isReplaceShown {
                replaceRow
            }
            HStack(spacing: 4) {
                OptionToggle(title: "Aa", help: "Match Case", isOn: $search.options.matchesCase)
                OptionToggle(title: "W", help: "Whole Words", isOn: $search.options.matchesWholeWord)
                OptionToggle(title: ".*", help: "Regular Expression", isOn: $search.options.usesRegularExpression)
                Spacer()
                if search.isSearching {
                    ProgressView().controlSize(.small)
                    Button("Stop") { search.cancel() }
                        .controlSize(.small)
                }
            }
            status
            replaceStatus
        }
        .padding(8)
        .onChange(of: search.options) {
            if search.searchedText != nil { model.runFolderSearch() }
        }
    }

    private var search: FolderSearchSession { model.search }

    private var replace: ReplaceSession { model.replace }

    private var replaceDisclosure: some View {
        Button {
            if replace.isReplaceShown { replace.isReplaceShown = false } else { replace.show() }
        } label: {
            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(replace.isReplaceShown ? 90 : 0))
                .frame(width: 14)
        }
        .buttonStyle(.borderless)
        .help(replace.isReplaceShown ? "Hide Replace" : "Show Replace (⌥⇧⌘F)")
        .accessibilityLabel(replace.isReplaceShown ? "Hide Replace" : "Show Replace")
    }

    private var replaceRow: some View {
        @Bindable var replace = model.replace
        return HStack(spacing: 4) {
            PanelSearchField(
                text: $replace.replacement,
                placeholder: "Replace",
                focusRequest: replace.focusRequest,
                onSubmit: { model.prepareReplaceAll() }
            )
            .accessibilityIdentifier("folder-replace-field")
            .padding(.leading, 18) // lines up with the search field, past the disclosure button
            if replace.isPreparing {
                ProgressView().controlSize(.small)
            }
            Button("Replace All…") { model.prepareReplaceAll() }
                .controlSize(.small)
                .disabled(!model.canReplaceAll)
                .help("Preview replacing every match, then confirm")
                .accessibilityIdentifier("replace-all-button")
        }
    }

    /// The Replace field's problem, or what the last Replace All (or its Undo) did.
    @ViewBuilder
    private var replaceStatus: some View {
        if let error = replace.error {
            Text(error.localizedDescription)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        } else if let outcome = replace.outcome {
            ReplaceOutcomeView(outcome: outcome, canUndo: replace.canUndo) { model.undoReplaceAll() }
        }
    }

    @ViewBuilder
    private var status: some View {
        if let error = search.error {
            Text(error.localizedDescription)
                .foregroundStyle(.red)
        } else if let searched = search.searchedText, !search.isSearching {
            Text(Self.summary(matches: search.matchCount, files: search.results.count, searched: searched, isTruncated: search.isTruncated))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("folder-search-summary")
        }
    }

    @ViewBuilder
    private var results: some View {
        if model.rootURL == nil {
            ContentUnavailableView("No Folder Open", systemImage: "magnifyingglass", description: Text("Open a folder to search its files."))
        } else {
            List {
                ForEach(search.results) { result in
                    Section {
                        ForEach(result.matches) { match in
                            MatchRow(match: match)
                                .contentShape(Rectangle())
                                .onTapGesture { model.open(match, in: result) }
                        }
                    } header: {
                        FileHeader(result: result)
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    /// "3 matches in 2 files", "No results for “x”", with a note when the search stopped early.
    static func summary(matches: Int, files: Int, searched: String, isTruncated: Bool) -> String {
        guard matches > 0 else { return "No results for “\(searched)”" }
        let text = "\(matches) \(matches == 1 ? "match" : "matches") in \(files) \(files == 1 ? "file" : "files")"
        return isTruncated ? text + " (stopped at \(matches); refine the search)" : text
    }
}

/// "Replaced 4 matches in 3 files." with Undo, and the files that were skipped and why.
private struct ReplaceOutcomeView: View {
    let outcome: ReplaceOutcome
    let canUndo: Bool
    let undo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(outcome.message)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("replace-outcome")
                Spacer(minLength: 4)
                if canUndo {
                    Button("Undo", action: undo)
                        .controlSize(.small)
                        .help("Undo Replace All: put back the files it wrote")
                }
            }
            ForEach(outcome.skipped) { skipped in
                Label("\(skipped.file.relativePath): \(skipped.reason.description)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct OptionToggle: View {
    let title: String
    let help: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .frame(minWidth: 18)
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct FileHeader: View {
    let result: FileSearchResult

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: result.file.kind.systemImage)
                .accessibilityHidden(true)
            Text(result.file.name)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(result.file.folderPath)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 4)
            Text("\(result.matches.count)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MatchRow: View {
    let match: TextMatch

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(match.lineNumber)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 24, alignment: .trailing)
            Text(highlightedPreview)
                .font(.callout)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Line \(match.lineNumber): \(match.preview)")
        .accessibilityAddTraits(.isButton)
    }

    /// The preview with the matched text in bold.
    private var highlightedPreview: AttributedString {
        let preview = match.preview as NSString
        let before = preview.substring(to: match.previewRange.location)
        let matched = preview.substring(with: match.previewRange)
        let after = preview.substring(from: NSMaxRange(match.previewRange))
        var highlighted = AttributedString(matched)
        highlighted.font = .callout.bold()
        return AttributedString(before) + highlighted + AttributedString(after)
    }
}
