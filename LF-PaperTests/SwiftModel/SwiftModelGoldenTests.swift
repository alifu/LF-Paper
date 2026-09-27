//
//  SwiftModelGoldenTests.swift
//  LF-PaperTests
//

import Foundation
import Testing
@testable import LF_Paper

/// The generated source for each model kind and option, compared with checked-in golden files
/// (`Golden/*.swift.golden`). `scripts/check-swift-models.sh` compiles the same files, since the
/// sandboxed test host can't run the compiler. A mismatch attaches the new output, to review
/// and copy over the golden file when the change is intended.
struct SwiftModelGoldenTests {
    private static let userJSON = """
        {
          "id": 42,
          "first_name": "Ada",
          "email": "ada@example.com",
          "is_active": true,
          "score": 9.5,
          "created_at": "2026-09-27T10:15:00Z",
          "website": "https://example.com/ada",
          "nickname": null,
          "default": "keyword",
          "address": {"street": "1 Main St", "city": "London", "geo": {"lat": 51.5, "lng": -0.12}},
          "tags": ["math", "poetry"],
          "orders": [
            {"order_id": 1, "total": 10, "items": [{"sku": "A1", "qty": 2}]},
            {"order_id": 2, "total": 12.5, "items": [], "coupon": "SAVE"}
          ],
          "ratings": [5, null, 4],
          "history": [],
          "metadata": [1, "two", {"three": 3}]
        }
        """

    /// Keys that clash with generated members or Swift itself, and an `id` that isn't `Hashable`.
    private static let edgeJSON = #"""
        {"self": "https://api.example.com/x", "CodingKeys": "x", "foo bar": 1, "id": {"value": 1}, "dictionary": 1, "jsonDictionary": 2}
        """#

    private static let usersJSON = #"[{"id": 1, "name": "Ada"}, {"id": 2, "name": "Grace", "email": null}]"#

    struct Case: CustomTestStringConvertible, Sendable {
        let golden: String
        let json: String
        let fileName: String
        let options: SwiftModelOptions

        var testDescription: String { golden }
    }

    private static func options(_ change: (inout SwiftModelOptions) -> Void = { _ in }) -> SwiftModelOptions {
        var options = SwiftModelOptions()
        options.rootName = "User"
        change(&options)
        return options
    }

    static let cases: [Case] = [
        Case(golden: "codable", json: userJSON, fileName: "user.json", options: options()),
        Case(golden: "decodable", json: userJSON, fileName: "user.json", options: options { $0.kind = .decodable }),
        Case(golden: "encodable", json: userJSON, fileName: "user.json", options: options { $0.kind = .encodable }),
        Case(golden: "classes", json: userJSON, fileName: "user.json", options: options {
            $0.kind = .classes
            $0.conformances = [.hashable, .sendable, .identifiable]
        }),
        Case(golden: "dictionary", json: userJSON, fileName: "user.json", options: options {
            $0.kind = .dictionary
            $0.conformances = [.identifiable, .hashable] // Hashable doesn't apply to dictionary-based models
        }),
        Case(golden: "public-var", json: userJSON, fileName: "user.json", options: options {
            $0.isPublic = true
            $0.usesVar = true
            $0.conformances = [.hashable, .equatable, .sendable, .identifiable]
        }),
        Case(golden: "keep-keys-plain-strings", json: userJSON, fileName: "user.json", options: options {
            $0.keyStyle = .keep
            $0.detectsDates = false
            $0.detectsURLs = false
        }),
        Case(golden: "edge-keys-classes", json: edgeJSON, fileName: "edge.json", options: options {
            $0.kind = .classes
            $0.keyStyle = .keep
            $0.conformances = [.identifiable]
        }),
        Case(golden: "edge-keys-public", json: edgeJSON, fileName: "edge.json", options: options {
            $0.isPublic = true
            $0.conformances = [.identifiable, .hashable]
        }),
        Case(golden: "edge-keys-dictionary", json: edgeJSON, fileName: "edge.json", options: options {
            $0.kind = .dictionary
            $0.conformances = [.identifiable]
        }),
        Case(golden: "root-array", json: usersJSON, fileName: "users.json", options: options()),
        Case(golden: "dictionary-root-array", json: usersJSON, fileName: "users.json", options: options { $0.kind = .dictionary }),
    ]

    @Test(arguments: cases)
    func generatedSourceMatchesTheGoldenFile(_ testCase: Case) throws {
        let value = try JSONParser.parse(testCase.json).value
        let schema = try SwiftModelSchema.make(
            from: value,
            rootName: testCase.options.rootName,
            keyStyle: testCase.options.keyStyle,
            inference: testCase.options.inference
        )
        let source = SwiftModelGenerator.source(for: schema, options: testCase.options, jsonFileName: testCase.fileName)

        let golden = Self.golden(named: testCase.golden)
        if source != golden {
            Attachment.record(source, named: "\(testCase.golden).swift.golden")
        }
        #expect(golden != nil, "missing Golden/\(testCase.golden).swift.golden; the output is attached")
        #expect(source == golden)
    }

    private static func golden(named name: String) -> String? {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: "\(name).swift", withExtension: "golden") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

private final class BundleToken {}
