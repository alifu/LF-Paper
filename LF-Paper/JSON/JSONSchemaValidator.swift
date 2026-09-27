//
//  JSONSchemaValidator.swift
//  LF-Paper
//

import Foundation

/// One way a document breaks its schema.
nonisolated struct SchemaProblem: Equatable, Sendable {
    let path: JSONPath
    let message: String
}

/// Checks a document against a JSON Schema: the commonly used keywords of drafts 4 to 2020-12.
///
/// Supported: boolean schemas, `type`, `enum`, `const`, `minimum`, `maximum`, `exclusiveMinimum`,
/// `exclusiveMaximum`, `multipleOf`, `minLength`, `maxLength`, `pattern`, `minItems`, `maxItems`,
/// `uniqueItems`, `items` (schema or tuple), `prefixItems`, `additionalItems`, `minProperties`,
/// `maxProperties`, `required`, `properties`, `patternProperties`, `additionalProperties`, `allOf`,
/// `anyOf`, `oneOf`, `not`, and `$ref` within the same schema. Other keywords (such as `format`) are ignored.
nonisolated enum JSONSchemaValidator {
    /// Nested schemas deeper than this are treated as a mistake rather than followed.
    private static let maximumDepth = 256

    static func validate(_ value: JSONValue, against schema: JSONValue) -> [SchemaProblem] {
        var validator = Validator(root: schema)
        validator.check(value, against: schema, at: .root, references: [], depth: 0)
        return validator.problems
    }

    private struct Validator {
        let root: JSONValue
        var problems: [SchemaProblem] = []

        mutating func report(_ message: String, at path: JSONPath) {
            problems.append(SchemaProblem(path: path, message: message))
        }

        /// `references` are the `$ref`s followed for this same value; seeing one again is a loop.
        mutating func check(_ value: JSONValue, against schema: JSONValue, at path: JSONPath, references: Set<String>, depth: Int) {
            guard depth < maximumDepth else {
                report("The schema is nested too deeply", at: path)
                return
            }
            switch schema {
            case .bool(true):
                return
            case .bool(false):
                report("No value is allowed here", at: path)
                return
            case .object(let members):
                let keywords = Keywords(members)
                checkReference(value, keywords, at: path, references: references, depth: depth)
                checkGeneral(value, keywords, at: path)
                switch value {
                case .number(let number): checkNumber(number, keywords, at: path)
                case .string(let text): checkString(text, keywords, at: path)
                case .array(let elements): checkArray(elements, keywords, at: path, depth: depth)
                case .object(let valueMembers): checkObject(valueMembers, keywords, at: path, depth: depth)
                case .bool, .null: break
                }
                checkCombinations(value, keywords, at: path, references: references, depth: depth)
            default:
                return // not a schema; nothing to check
            }
        }

        // MARK: Keywords for any value

        private mutating func checkReference(_ value: JSONValue, _ keywords: Keywords, at path: JSONPath, references: Set<String>, depth: Int) {
            guard case .string(let reference)? = keywords["$ref"] else { return }
            guard reference.hasPrefix("#") else {
                report("Only $ref inside the same schema (starting with #) is supported", at: path)
                return
            }
            guard !references.contains(reference) else {
                report("The schema’s $ref goes round in a circle", at: path)
                return
            }
            guard let target = JSONPointer.resolve(String(reference.dropFirst()), in: root) else {
                report("The schema’s $ref “\(reference)” doesn’t point to anything", at: path)
                return
            }
            check(value, against: target, at: path, references: references.union([reference]), depth: depth + 1)
        }

        private mutating func checkGeneral(_ value: JSONValue, _ keywords: Keywords, at path: JSONPath) {
            if let type = keywords["type"] {
                let allowed: [String] = switch type {
                case .string(let name): [name]
                case .array(let names): names.compactMap { if case .string(let name) = $0 { name } else { nil } }
                default: []
                }
                if !allowed.isEmpty, !allowed.contains(where: { JSONSchemaTypes.value(value, isOfType: $0) }) {
                    let expected = allowed.map(JSONSchemaTypes.describe).joined(separator: " or ")
                    report("Expected \(expected), found \(JSONSchemaTypes.describe(value))", at: path)
                }
            }
            if case .array(let options)? = keywords["enum"], !options.contains(where: { JSONEquality.isEqual($0, value) }) {
                report("Must be one of: \(options.map { JSONFormatter.minified($0) }.joined(separator: ", "))", at: path)
            }
            if let constant = keywords["const"], !JSONEquality.isEqual(constant, value) {
                report("Must be \(JSONFormatter.minified(constant))", at: path)
            }
        }

        // MARK: Numbers, strings

        private mutating func checkNumber(_ number: JSONNumber, _ keywords: Keywords, at path: JSONPath) {
            guard let value = Double(number.literal) else { return }
            if let minimum = keywords.number("minimum"), value < minimum {
                report("Must be at least \(format(minimum))", at: path)
            }
            if let maximum = keywords.number("maximum"), value > maximum {
                report("Must be at most \(format(maximum))", at: path)
            }
            if let minimum = keywords.number("exclusiveMinimum"), value <= minimum {
                report("Must be more than \(format(minimum))", at: path)
            }
            if let maximum = keywords.number("exclusiveMaximum"), value >= maximum {
                report("Must be less than \(format(maximum))", at: path)
            }
            if let divisor = keywords.number("multipleOf"), divisor > 0 {
                let quotient = value / divisor
                if abs(quotient - quotient.rounded()) > 1e-9 * max(1, abs(quotient)) {
                    report("Must be a multiple of \(format(divisor))", at: path)
                }
            }
        }

        private mutating func checkString(_ text: String, _ keywords: Keywords, at path: JSONPath) {
            let length = text.unicodeScalars.count // JSON Schema counts code points
            if let minimum = keywords.integer("minLength"), length < minimum {
                report("Must be at least \(minimum) \(minimum == 1 ? "character" : "characters")", at: path)
            }
            if let maximum = keywords.integer("maxLength"), length > maximum {
                report("Must be at most \(maximum) \(maximum == 1 ? "character" : "characters")", at: path)
            }
            if case .string(let pattern)? = keywords["pattern"] {
                guard let expression = try? NSRegularExpression(pattern: pattern) else {
                    report("The schema’s pattern \(pattern) isn’t a valid regular expression", at: path)
                    return
                }
                if expression.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) == nil {
                    report("Must match the pattern \(pattern)", at: path)
                }
            }
        }

        // MARK: Arrays

        private mutating func checkArray(_ elements: [JSONValue], _ keywords: Keywords, at path: JSONPath, depth: Int) {
            if let minimum = keywords.integer("minItems"), elements.count < minimum {
                report("Must have at least \(minimum) \(minimum == 1 ? "item" : "items")", at: path)
            }
            if let maximum = keywords.integer("maxItems"), elements.count > maximum {
                report("Must have at most \(maximum) \(maximum == 1 ? "item" : "items")", at: path)
            }
            if case .bool(true)? = keywords["uniqueItems"], let (first, second) = firstDuplicate(in: elements) {
                report("Items must be unique ([\(first)] and [\(second)] are the same)", at: path)
            }

            // A tuple (prefixItems, or items as an array in older drafts), then one schema for the rest.
            var tuple: [JSONValue] = []
            var rest: JSONValue?
            if case .array(let schemas)? = keywords["prefixItems"] {
                tuple = schemas
                rest = keywords["items"]
            } else if case .array(let schemas)? = keywords["items"] {
                tuple = schemas
                rest = keywords["additionalItems"]
            } else {
                rest = keywords["items"]
            }
            for (index, element) in elements.enumerated() {
                let schema = index < tuple.count ? tuple[index] : rest
                if let schema {
                    check(element, against: schema, at: path.appending(.index(index)), references: [], depth: depth + 1)
                }
            }
        }

        private func firstDuplicate(in elements: [JSONValue]) -> (Int, Int)? {
            for second in elements.indices {
                for first in 0..<second where JSONEquality.isEqual(elements[first], elements[second]) {
                    return (first, second)
                }
            }
            return nil
        }

        // MARK: Objects

        private mutating func checkObject(_ members: [JSONMember], _ keywords: Keywords, at path: JSONPath, depth: Int) {
            if let minimum = keywords.integer("minProperties"), members.count < minimum {
                report("Must have at least \(minimum) \(minimum == 1 ? "property" : "properties")", at: path)
            }
            if let maximum = keywords.integer("maxProperties"), members.count > maximum {
                report("Must have at most \(maximum) \(maximum == 1 ? "property" : "properties")", at: path)
            }
            if case .array(let required)? = keywords["required"] {
                let present = Set(members.map(\.key))
                for case .string(let name) in required where !present.contains(name) {
                    report("“\(name)” is required", at: path)
                }
            }

            let properties = Keywords(keywords["properties"])
            let patterns: [(NSRegularExpression, JSONValue)] = Keywords(keywords["patternProperties"]).members.compactMap { member in
                (try? NSRegularExpression(pattern: member.key)).map { ($0, member.value) }
            }
            for member in members {
                let memberPath = path.appending(.key(member.key))
                var isKnown = false
                if let schema = properties[member.key] {
                    isKnown = true
                    check(member.value, against: schema, at: memberPath, references: [], depth: depth + 1)
                }
                let keyRange = NSRange(location: 0, length: (member.key as NSString).length)
                for (expression, schema) in patterns where expression.firstMatch(in: member.key, range: keyRange) != nil {
                    isKnown = true
                    check(member.value, against: schema, at: memberPath, references: [], depth: depth + 1)
                }
                guard !isKnown, let additional = keywords["additionalProperties"] else { continue }
                if case .bool(false) = additional {
                    report("“\(member.key)” isn’t allowed here", at: memberPath)
                } else {
                    check(member.value, against: additional, at: memberPath, references: [], depth: depth + 1)
                }
            }
        }

        // MARK: Combinations

        private mutating func checkCombinations(_ value: JSONValue, _ keywords: Keywords, at path: JSONPath, references: Set<String>, depth: Int) {
            if case .array(let schemas)? = keywords["allOf"] {
                for schema in schemas {
                    check(value, against: schema, at: path, references: references, depth: depth + 1)
                }
            }
            if case .array(let schemas)? = keywords["anyOf"], !schemas.contains(where: { matches(value, $0, references, depth) }) {
                report("Doesn’t match any of the allowed shapes (anyOf)", at: path)
            }
            if case .array(let schemas)? = keywords["oneOf"] {
                let matching = schemas.filter { matches(value, $0, references, depth) }.count
                if matching == 0 {
                    report("Doesn’t match any of the allowed shapes (oneOf)", at: path)
                } else if matching > 1 {
                    report("Must match exactly one of the allowed shapes, but matches \(matching) (oneOf)", at: path)
                }
            }
            if let schema = keywords["not"], matches(value, schema, references, depth) {
                report("Must not match the schema in “not”", at: path)
            }
        }

        /// Whether the value passes a schema, without reporting that schema's own problems.
        private func matches(_ value: JSONValue, _ schema: JSONValue, _ references: Set<String>, _ depth: Int) -> Bool {
            var trial = Validator(root: root)
            trial.check(value, against: schema, at: .root, references: references, depth: depth + 1)
            return trial.problems.isEmpty
        }

        private func format(_ number: Double) -> String {
            number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(number)
        }
    }

    /// A schema object's keywords, looked up by name (the last one wins for duplicates).
    private struct Keywords {
        let members: [JSONMember]

        init(_ members: [JSONMember]) {
            self.members = members
        }

        init(_ value: JSONValue?) {
            if case .object(let members)? = value {
                self.members = members
            } else {
                self.members = []
            }
        }

        subscript(_ name: String) -> JSONValue? {
            members.last { $0.key == name }?.value
        }

        func number(_ name: String) -> Double? {
            guard case .number(let number)? = self[name] else { return nil }
            return Double(number.literal)
        }

        func integer(_ name: String) -> Int? {
            number(name).flatMap { $0 >= 0 && $0 < Double(Int.max) ? Int($0) : nil }
        }
    }
}
