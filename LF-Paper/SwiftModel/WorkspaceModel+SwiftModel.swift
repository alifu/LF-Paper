//
//  WorkspaceModel+SwiftModel.swift
//  LF-Paper
//

import Foundation

/// JSON › Generate Swift Model: a sheet with options and a live preview; the code opens in a new, unsaved tab.
extension WorkspaceModel {
    /// A JSON document that currently parses.
    var canGenerateSwiftModel: Bool {
        isJSONDocument && json.status == .valid
    }

    /// Opens the sheet for the active JSON document, or explains why its JSON can't be used.
    func showSwiftModelGenerator() {
        guard let document, isJSONDocument else { return }
        do throws(JSONParseError) {
            let value = try JSONParser.parse(document.text).value
            swiftModelGenerator = SwiftModelSession(value: value, jsonFileURL: document.url)
        } catch {
            presentedError = .conversionFailed("Fix the JSON first: \(error.localizedDescription)")
        }
    }

    /// Opens the generated code in a new tab (such as `User.swift` next to `users.json`) and closes the sheet.
    func openGeneratedSwiftModel() {
        guard let session = swiftModelGenerator, let source = session.source else { return }
        openNewFile(source, fileExtension: "swift", nextTo: session.jsonFileURL, baseName: session.rootName)
        swiftModelGenerator = nil
    }
}
