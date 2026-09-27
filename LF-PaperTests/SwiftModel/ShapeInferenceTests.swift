//
//  ShapeInferenceTests.swift
//  LF-PaperTests
//

import Testing
@testable import LF_Paper

/// What each JSON position holds across the whole sample.
struct ShapeInferenceTests {
    private func shape(_ json: String, options: ShapeInference.Options = ShapeInference.Options()) throws -> Shaped {
        ShapeInference.shape(of: try JSONParser.parse(json).value, options: options)
    }

    private func required(_ shape: ValueShape) -> Shaped { Shaped(shape: shape, isOptional: false) }
    private func optional(_ shape: ValueShape?) -> Shaped { Shaped(shape: shape, isOptional: true) }

    @Test func scalars() throws {
        #expect(try shape("true") == required(.bool))
        #expect(try shape("12") == required(.int))
        #expect(try shape("-3") == required(.int))
        #expect(try shape("1.5") == required(.double))
        #expect(try shape("1e3") == required(.double))
        #expect(try shape("123456789012345678901234567890") == required(.double)) // too big for Int
        #expect(try shape(#""text""#) == required(.string))
        #expect(try shape("null") == optional(nil))
    }

    @Test func datesAndWebAddressesAreDetectedWhenAsked() throws {
        #expect(try shape(#""2026-09-27T10:15:00Z""#) == required(.date))
        #expect(try shape(#""2026-09-27T10:15:00+07:00""#) == required(.date))
        #expect(try shape(#""https://example.com/a?b=c""#) == required(.url))
        #expect(try shape(#""http://example.com""#) == required(.url))
        #expect(try shape(#""2026-09-27""#) == required(.string)) // not a full ISO 8601 date and time
        #expect(try shape(#""2026-09-27T10:15:00.123Z""#) == required(.string)) // .iso8601 decoding rejects fractions
        #expect(try shape(#""example.com""#) == required(.string))
        #expect(try shape(#""https://""#) == required(.string))

        let off = ShapeInference.Options(detectsDates: false, detectsURLs: false)
        #expect(try shape(#""2026-09-27T10:15:00Z""#, options: off) == required(.string))
        #expect(try shape(#""https://example.com""#, options: off) == required(.string))
    }

    @Test func objectsKeepTheirKeyOrder() throws {
        let result = try shape(#"{"b": 1, "a": "x", "c": {"d": true}}"#)

        #expect(result == required(.object([
            FieldShape(key: "b", value: required(.int)),
            FieldShape(key: "a", value: required(.string)),
            FieldShape(key: "c", value: required(.object([FieldShape(key: "d", value: required(.bool))]))),
        ])))
    }

    @Test func duplicateKeysKeepTheirFirstPlaceAndLastValue() throws {
        let result = try shape(#"{"a": 1, "b": 2, "a": "x"}"#)

        #expect(result == required(.object([
            FieldShape(key: "a", value: required(.string)),
            FieldShape(key: "b", value: required(.int)),
        ])))
    }

    @Test func arrayItemsAreMergedIntoOneType() throws {
        let result = try shape(#"[{"id": 1, "name": "a"}, {"id": 2, "email": "e"}, {"id": 3, "name": null}]"#)

        #expect(result == required(.array(required(.object([
            FieldShape(key: "id", value: required(.int)),
            FieldShape(key: "name", value: optional(.string)),
            FieldShape(key: "email", value: optional(.string)),
        ])))))
    }

    @Test func intAndDoubleTogetherAreDouble() throws {
        #expect(try shape("[1, 2.5, 3]") == required(.array(required(.double))))
    }

    @Test func nullItemsMakeTheItemsOptional() throws {
        #expect(try shape(#"["a", null]"#) == required(.array(optional(.string))))
    }

    @Test func emptyArraysHaveNoItemType() throws {
        #expect(try shape("[]") == required(.array(nil)))
        #expect(try shape("[[], [1]]") == required(.array(required(.array(required(.int))))))
    }

    @Test func reallyDifferentTypesAreMixed() throws {
        #expect(try shape(#"[1, "a"]"#) == required(.array(required(.mixed))))
        #expect(try shape(#"[{"a": 1}, [1]]"#) == required(.array(required(.mixed))))
        #expect(try shape(#"[true, 1]"#) == required(.array(required(.mixed))))
    }

    @Test func datesAndAddressesMixedWithTextAreText() throws {
        #expect(try shape(#"["2026-09-27T10:15:00Z", "soon"]"#) == required(.array(required(.string))))
        #expect(try shape(#"["https://a.com", "a"]"#) == required(.array(required(.string))))
        #expect(try shape(#"["https://a.com", "2026-09-27T10:15:00Z"]"#) == required(.array(required(.string))))
    }

    @Test func nestedObjectsInArraysMergeToo() throws {
        let result = try shape(#"[{"tags": [{"x": 1}]}, {"tags": [{"y": 2}]}]"#)

        #expect(result == required(.array(required(.object([
            FieldShape(key: "tags", value: required(.array(required(.object([
                FieldShape(key: "x", value: optional(.int)),
                FieldShape(key: "y", value: optional(.int)),
            ]))))),
        ])))))
    }
}
