//
//  SchemaSession.swift
//  LF-Paper
//

import Foundation
import Observation

/// Which schema a document is checked against, per document.
enum SchemaChoice: Equatable, Sendable {
    /// The document's own `$schema`, when it names a local file.
    case automatic
    case file(URL)
    case off
}

/// Where a document's schema comes from.
nonisolated enum SchemaSource: Equatable, Sendable {
    case none
    case off
    /// `$schema` is a web address. Schemas aren't downloaded; only local files are used.
    case remote(String)
    case file(URL)

    /// `$schema` is a path relative to the document, or a `file:` URL.
    static func resolve(choice: SchemaChoice, document: JSONValue, documentURL: URL) -> SchemaSource {
        switch choice {
        case .off:
            return .off
        case .file(let url):
            return .file(url)
        case .automatic:
            guard case .object(let members) = document,
                  case .string(let reference)? = members.last(where: { $0.key == "$schema" })?.value,
                  !reference.isEmpty
            else { return .none }
            if let url = URL(string: reference), let scheme = url.scheme?.lowercased() {
                return scheme == "file" ? .file(URL(filePath: url.path(percentEncoded: false))) : .remote(reference)
            }
            let folder = documentURL.deletingLastPathComponent()
            return .file(folder.appending(path: reference, directoryHint: .notDirectory).standardizedFileURL)
        }
    }
}

/// A schema problem ready to show: where it is in the text, so clicking it can reveal it.
nonisolated struct SchemaIssue: Identifiable, Equatable, Sendable {
    let id: Int
    let path: JSONPath
    let message: String
    /// 1-based line, when the path is found in the text.
    let line: Int?
    let range: NSRange?
}

/// What the schema panel shows.
nonisolated enum SchemaState: Equatable, Sendable {
    /// Automatic, and the document names no schema.
    case none
    case off
    case remote(String)
    case unreadable(schemaName: String, reason: String)
    case checked(schemaName: String, issues: [SchemaIssue])
}

/// Checks the open JSON document against its schema in the background.
@Observable
final class SchemaSession {
    private(set) var state = SchemaState.none
    private var choices: [URL: SchemaChoice] = [:]

    func choice(for documentURL: URL) -> SchemaChoice {
        choices[documentURL.standardizedFileURL] ?? .automatic
    }

    func setChoice(_ choice: SchemaChoice, for documentURL: URL) {
        choices[documentURL.standardizedFileURL] = choice
    }

    /// `document` is the parse of `text` with source ranges, so problems get lines and ranges.
    func check(document: JSONDocument, text: String, documentURL: URL) async {
        let source = SchemaSource.resolve(choice: choice(for: documentURL), document: document.value, documentURL: documentURL)
        state = await Self.run(source: source, document: document, text: text)
    }

    @concurrent
    private static func run(source: SchemaSource, document: JSONDocument, text: String) async -> SchemaState {
        switch source {
        case .none: return .none
        case .off: return .off
        case .remote(let address): return .remote(address)
        case .file(let url):
            let name = url.lastPathComponent
            let schema: JSONValue
            do throws(AppError) {
                let schemaText = try LocalFileService().read(url)
                do throws(JSONParseError) {
                    schema = try JSONParser.parse(schemaText).value
                } catch {
                    return .unreadable(schemaName: name, reason: error.localizedDescription)
                }
            } catch {
                return .unreadable(schemaName: name, reason: error.localizedDescription)
            }
            let lines = LineIndex(text: text as NSString)
            let issues = JSONSchemaValidator.validate(document.value, against: schema).enumerated().map { index, problem in
                let range = document.sourceRanges[problem.path]
                return SchemaIssue(
                    id: index,
                    path: problem.path,
                    message: problem.message,
                    line: range.map { lines.lineNumber(at: $0.location) },
                    range: range
                )
            }
            return .checked(schemaName: name, issues: issues)
        }
    }
}
