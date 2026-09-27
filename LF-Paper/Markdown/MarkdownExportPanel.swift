//
//  MarkdownExportPanel.swift
//  LF-Paper
//

import AppKit
import UniformTypeIdentifiers

/// File › Export as HTML / PDF: asks where to save (which also grants the sandboxed app access
/// to that file), then writes the export. Failures show in the window's usual error alert.
enum MarkdownExportPanel {
    enum Format {
        case html, pdf

        var contentType: UTType {
            switch self {
            case .html: .html
            case .pdf: .pdf
            }
        }
    }

    static func export(_ format: Format, from workspace: WorkspaceModel) {
        guard let document = workspace.document, workspace.isMarkdownDocument else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = document.url.deletingPathExtension().lastPathComponent
        panel.directoryURL = document.url.deletingLastPathComponent()
        panel.canCreateDirectories = true
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            write(format, markdown: document.text, documentURL: document.url, workspace: workspace, to: url)
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    private static func write(_ format: Format, markdown: String, documentURL: URL, workspace: WorkspaceModel, to url: URL) {
        Task {
            do throws(AppError) {
                switch format {
                case .html:
                    let title = MarkdownExport.title(for: markdown, fileName: documentURL.lastPathComponent)
                    try MarkdownExport.writeHTML(markdown: markdown, title: title, to: url)
                case .pdf:
                    try await MarkdownPDFExporter().write(
                        markdown: markdown,
                        documentFolder: documentURL.deletingLastPathComponent(),
                        workspaceRoot: workspace.rootURL,
                        to: url
                    )
                }
            } catch {
                workspace.presentedError = error
            }
        }
    }
}
