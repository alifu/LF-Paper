//
//  SwiftModelSession.swift
//  LF-Paper
//

import Foundation
import Observation

/// The Generate Swift Model sheet: the options, and the code they produce, updated as they change.
@Observable
final class SwiftModelSession: Identifiable {
    /// The JSON file the model is made from.
    let jsonFileURL: URL
    var options: SwiftModelOptions {
        didSet {
            if options != oldValue { regenerate() }
        }
    }
    /// The generated code, or `nil` when the JSON can't be modelled (see `error`).
    private(set) var source: String?
    private(set) var error: SwiftModelError?
    /// The root type's name as generated (cleaned up from the option).
    private(set) var rootName: String

    @ObservationIgnored private let value: JSONValue
    /// Inference is the slow part for big files, and only the detection options change it.
    @ObservationIgnored private var cachedShape: (options: ShapeInference.Options, shape: Shaped)?

    init(value: JSONValue, jsonFileURL: URL) {
        self.value = value
        self.jsonFileURL = jsonFileURL
        var options = SwiftModelOptions()
        options.rootName = SwiftNaming.rootTypeName(forFileNamed: jsonFileURL.lastPathComponent)
        self.options = options
        rootName = options.rootName
        regenerate()
    }

    /// The new tab's name.
    var fileName: String { "\(rootName).swift" }

    private func regenerate() {
        do throws(SwiftModelError) {
            let schema = try SwiftModelSchema.make(
                from: shape(),
                rootName: options.rootName,
                keyStyle: options.keyStyle
            )
            rootName = schema.rootName
            source = SwiftModelGenerator.source(for: schema, options: options, jsonFileName: jsonFileURL.lastPathComponent)
            error = nil
        } catch {
            source = nil
            self.error = error
        }
    }

    private func shape() -> Shaped {
        if let cachedShape, cachedShape.options == options.inference { return cachedShape.shape }
        let shape = ShapeInference.shape(of: value, options: options.inference)
        cachedShape = (options.inference, shape)
        return shape
    }
}
