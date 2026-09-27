//
//  WorkspaceModel+JSON.swift
//  LF-Paper
//

import Foundation

/// JSON actions on the open document.
extension WorkspaceModel {
    func formatJSON(indentation: JSONFormatter.Indentation = .spaces(2), sortsKeys: Bool = false) {
        rewriteJSON { JSONFormatter.pretty($0, indentation: indentation, sortsKeys: sortsKeys) }
    }

    func minifyJSON() {
        rewriteJSON { JSONFormatter.minified($0) }
    }

    /// Puts the cursor at the error and focuses the editor so it can be fixed.
    func revealJSONError(_ error: JSONParseError) {
        reveal(NSRange(location: error.offset, length: 0), focusesEditor: true)
    }

    /// Highlights a value's source text (from the last successful parse); keeps focus where it is.
    func revealJSONValue(at path: JSONPath) {
        guard let range = json.sourceRanges[path] else { return }
        reveal(range, focusesEditor: false)
    }

    /// Checks the open JSON file against its schema, using the latest valid parse.
    /// While the text has a syntax error the previous result stays.
    func checkSchema() async {
        guard let document, isJSONDocument, json.status == .valid, let parsed = json.lastValid else { return }
        await schema.check(document: parsed, text: document.text, documentURL: document.url)
    }

    /// Selects a schema problem in the editor.
    func reveal(_ issue: SchemaIssue) {
        guard let range = issue.range else { return }
        reveal(range, focusesEditor: true)
    }

    /// Replaces the document text with `transform(parsed value)`, as an ordinary (undoable) edit.
    /// A final newline is kept if the file had one. Invalid JSON is left alone and its error shown.
    private func rewriteJSON(_ transform: (JSONValue) -> String) {
        guard let text = document?.text else { return }
        do throws(JSONParseError) {
            let value = try JSONParser.parse(text).value
            let rewritten = transform(value) + (text.hasSuffix("\n") ? "\n" : "")
            if rewritten != text {
                updateDocumentText(rewritten)
            }
        } catch {
            revealJSONError(error)
        }
    }
}
