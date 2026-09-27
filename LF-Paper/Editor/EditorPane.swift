//
//  EditorPane.swift
//  LF-Paper
//

import SwiftUI

/// The editor column: the scratchpad, the open document, or a hint when neither is showing.
struct EditorPane: View {
    /// What the one editor shows. Keeping a single `CodeTextView` (rather than one per branch)
    /// keeps its coordinator, and with it every document's undo history, across switches.
    private struct Content {
        let text: String
        let id: UUID
        let fileKind: FileKind?
        let onTextChange: @MainActor (String) -> Void
    }

    let model: WorkspaceModel
    @AppStorage(AppSettings.Key.editorFontSize) private var fontSize = AppSettings.defaultFontSize
    @AppStorage(AppSettings.Key.wrapsLines) private var wrapsLines = AppSettings.defaultWrapsLines

    var body: some View {
        if let content {
            VStack(spacing: 0) {
                if model.isScratchpadActive {
                    ScratchpadBar(model: model)
                    Divider()
                } else {
                    documentBars
                }
                CodeTextView(
                    text: content.text,
                    documentID: content.id,
                    fileKind: content.fileKind,
                    fontSize: CGFloat(AppSettings.clampedFontSize(fontSize)),
                    openDocumentIDs: model.editorDocumentIDs,
                    wrapsLines: model.wrapsLines(preference: wrapsLines),
                    revealRequest: model.revealRequest,
                    onTextChange: content.onTextChange,
                    onSelectionChange: { model.noteSelection($1, in: $0) },
                    scrollRequest: model.scrollSync.editorRequest(for: content.id),
                    onScrollLine: { model.editorDidScroll(toLine: $1, in: $0) }
                )
            }
        } else {
            ContentUnavailableView(
                "No File Selected",
                systemImage: "doc.text",
                description: Text("Select a Markdown or JSON file in the sidebar, or write in the Scratch tab.")
            )
        }
    }

    private var content: Content? {
        if model.isScratchpadActive {
            return Content(text: model.scratchpadText, id: model.scratchpadID, fileKind: nil) { model.updateScratchpadText($0) }
        }
        return model.document.map { document in
            Content(
                text: document.text,
                id: document.id,
                // Highlighting a very long line on every keystroke is too slow.
                fileKind: model.editsAsPlainText ? nil : FileKind(fileExtension: document.url.pathExtension)
            ) { model.updateDocumentText($0) }
        }
    }

    @ViewBuilder
    private var documentBars: some View {
        if let document = model.document, model.isDocumentMissingOnDisk {
            MissingFileBanner(fileName: document.url.lastPathComponent) {
                _ = model.save()
            }
        }
        if model.offersFormatting, let document = model.document {
            FormatOfferBanner(fileName: document.url.lastPathComponent, model: model)
        }
        if model.isJSONDocument {
            JSONEditorBar(model: model)
            Divider()
        }
    }
}

/// For minified JSON: formatting makes it readable and fast to edit with highlighting again.
private struct FormatOfferBanner: View {
    let fileName: String
    let model: WorkspaceModel
    @AppStorage(AppSettings.Key.jsonIndentation) private var indentation = JSONIndentationSetting.twoSpaces

    var body: some View {
        HStack {
            Label("“\(fileName)” is on one very long line, so it’s wrapped and shown without highlighting.", systemImage: "text.alignleft")
                .lineLimit(2)
            Spacer()
            Button("Not Now") { model.declineFormatting() }
            Button("Format") { model.formatJSON(indentation: indentation.indentation) }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.blue.opacity(0.12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("format-offer")
    }
}

private struct MissingFileBanner: View {
    let fileName: String
    let onSave: () -> Void

    var body: some View {
        HStack {
            Label("“\(fileName)” was deleted from disk.", systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
            Spacer()
            Button("Save to Recreate", action: onSave)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.15))
    }
}
