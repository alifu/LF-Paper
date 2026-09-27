//
//  WorkspaceModel+Document.swift
//  LF-Paper
//

import Foundation

/// How the active document is edited: its kind, very long lines and line wrapping.
extension WorkspaceModel {
    var isJSONDocument: Bool {
        document.map { FileKind(fileExtension: $0.url.pathExtension) == .json } ?? false
    }

    /// The active file has a line so long (usually minified JSON) that it's edited without highlighting.
    var editsAsPlainText: Bool {
        guard let document else { return false }
        let length = (document.text as NSString).length
        if let check = longLineChecks[document.id], check.length == length {
            return check.hasLongLine
        }
        let hasLongLine = LongLines.containsLongLine(document.text)
        longLineChecks[document.id] = (length, hasLongLine)
        return hasLongLine
    }

    /// Offer to format a JSON file with a very long line, unless that was turned down.
    var offersFormatting: Bool {
        guard let document, isJSONDocument, !declinedFormatOffers.contains(document.id) else { return false }
        return editsAsPlainText
    }

    /// Whether the editor wraps lines, given the View › Wrap Lines setting. The scratchpad (prose)
    /// always wraps, and so do files with a very long line: laying out a megabyte-long line on every
    /// keystroke makes typing slow (about 0.3 s instead of 16 ms).
    func wrapsLines(preference: Bool) -> Bool {
        isScratchpadActive || editsAsPlainText || preference
    }

    func declineFormatting() {
        guard let document else { return }
        declinedFormatOffers.insert(document.id)
    }
}
