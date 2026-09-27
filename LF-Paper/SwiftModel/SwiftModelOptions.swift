//
//  SwiftModelOptions.swift
//  LF-Paper
//

import Foundation

/// The choices in the Generate Swift Model sheet.
nonisolated struct SwiftModelOptions: Equatable, Sendable {
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case codable
        case decodable
        case encodable
        /// `final class` with an initializer, `Codable`.
        case classes
        /// `init?(dictionary:)` and `var dictionary`, for `JSONSerialization`.
        case dictionary

        var id: Self { self }

        var title: String {
            switch self {
            case .codable: "Codable structs"
            case .decodable: "Decodable structs"
            case .encodable: "Encodable structs"
            case .classes: "Codable classes"
            case .dictionary: "Dictionary-based structs"
            }
        }

        var usesCodable: Bool { self != .dictionary }
    }

    enum KeyStyle: String, CaseIterable, Identifiable, Sendable {
        /// camelCase properties, with `CodingKeys` for the JSON names that differ.
        case camelCase
        /// The JSON names as they are, when they're valid Swift.
        case keep

        var id: Self { self }

        var title: String {
            switch self {
            case .camelCase: "camelCase"
            case .keep: "As in the JSON"
            }
        }
    }

    /// In the order they're written after the type's name.
    enum Conformance: String, CaseIterable, Identifiable, Sendable {
        case hashable = "Hashable"
        case equatable = "Equatable"
        /// Only on types that have an `id` property.
        case identifiable = "Identifiable"
        case sendable = "Sendable"

        var id: Self { self }
    }

    var kind = Kind.codable
    var rootName = "Root"
    var usesVar = false
    var isPublic = false
    var conformances: Set<Conformance> = []
    var keyStyle = KeyStyle.camelCase
    var detectsDates = true
    var detectsURLs = true

    var inference: ShapeInference.Options {
        ShapeInference.Options(detectsDates: detectsDates, detectsURLs: detectsURLs)
    }

    /// Whether a conformance can be chosen with the other options: dictionary-based models hold
    /// `Any`, so only `Identifiable` works there; a class with `var` properties can't be `Sendable`.
    func allows(_ conformance: Conformance) -> Bool {
        switch (kind, conformance) {
        case (.dictionary, .identifiable): true
        case (.dictionary, _): false
        case (.classes, .sendable): !usesVar
        default: true
        }
    }

    /// The chosen conformances that apply, in a fixed order; `Hashable` implies `Equatable`.
    var effectiveConformances: [Conformance] {
        let chosen = conformances.filter(allows)
        return Conformance.allCases.filter { conformance in
            chosen.contains(conformance) && !(conformance == .equatable && chosen.contains(.hashable))
        }
    }
}
