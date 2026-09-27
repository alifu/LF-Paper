//
//  WorkspaceModel+Convert.swift
//  LF-Paper
//

import Foundation

/// JSON › Convert: the result opens in a new, unsaved tab next to the file.
extension WorkspaceModel {
    private var activeKind: FileKind? {
        document.flatMap { FileKind(fileExtension: $0.url.pathExtension) }
    }

    var canConvertFromJSON: Bool { activeKind == .json }
    var canConvertToJSON: Bool { activeKind == .yaml || activeKind == .csv }

    func convertToYAML() {
        convertJSON(toExtension: "yaml", with: YAMLConversion.yaml(from:))
    }

    func convertToCSV() {
        convertJSON(toExtension: "csv", with: CSVConversion.csv(from:))
    }

    /// YAML or CSV to JSON, formatted with the given indentation.
    func convertToJSON(indentation: JSONFormatter.Indentation) {
        guard let document, let kind = activeKind, canConvertToJSON else { return }
        do throws(ConversionError) {
            let value = kind == .yaml
                ? try YAMLConversion.json(fromYAML: document.text)
                : try CSVConversion.json(fromCSV: document.text)
            openNewFile(JSONFormatter.pretty(value, indentation: indentation) + "\n", fileExtension: "json", nextTo: document.url)
        } catch {
            presentedError = .conversionFailed(error.message)
        }
    }

    private func convertJSON(toExtension fileExtension: String, with convert: (JSONValue) throws(ConversionError) -> String) {
        guard let document, canConvertFromJSON else { return }
        let value: JSONValue
        do throws(JSONParseError) {
            value = try JSONParser.parse(document.text).value
        } catch {
            presentedError = .conversionFailed("Fix the JSON first: \(error.localizedDescription)")
            return
        }
        do throws(ConversionError) {
            openNewFile(try convert(value), fileExtension: fileExtension, nextTo: document.url)
        } catch {
            presentedError = .conversionFailed(error.message)
        }
    }
}
