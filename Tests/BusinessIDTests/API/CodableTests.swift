import Foundation
import Testing

@testable import BusinessID

/// Serialization is optional, but where it exists the names and values follow
/// the common model: an enum is the lower case string the specification names,
/// never an ordinal.
@Suite("Codable")
struct CodableTests {
    private func encoded<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("Enum values serialize as the strings the specification names")
    func enumSpellings() throws {
        #expect(StepStatus.notRun.rawValue == "not_run")
        #expect(ValidationLevel.checksum.rawValue == "checksum")
        #expect(ValidationProfile.strictCurrent.rawValue == "strict_current")
        #expect(ReasonCode.notRunFormatUnsupported.rawValue == "not_run_format_unsupported")
        #expect(ReasonCode.checksumNotPublished.rawValue == "checksum_not_published")
        #expect(ReasonCode.invalidEncoding.rawValue == "invalid_encoding")

        // Every case is a lower snake case token, which is what a consumer of
        // the JSON matches on.
        for reason in ReasonCode.allCases {
            #expect(
                reason.rawValue.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" },
                Comment(rawValue: reason.rawValue)
            )
        }
    }

    @Test("A report round trips through JSON")
    func reportRoundTrip() throws {
        let report = BusinessIDEngine.default.validate(
            IdentifierInput(kind: "siren", value: "  012 345-674 ")
        )
        let data = try JSONEncoder().encode(report)
        #expect(try JSONDecoder().decode(ValidationReport.self, from: data) == report)
    }

    @Test("A canonicalization result round trips through JSON")
    func canonicalizationRoundTrip() throws {
        let result = BusinessIDEngine.default.canonicalize(
            IdentifierInput(kind: "vat", value: "gr 012345670")
        )
        let data = try JSONEncoder().encode(result)
        #expect(try JSONDecoder().decode(CanonicalizationResult.self, from: data) == result)
    }

    @Test("A report carries the common field names")
    func reportFieldNames() throws {
        let object = try encoded(
            BusinessIDEngine.default.validate(IdentifierInput(kind: "siren", value: "012345674"))
        )
        let expected: Set<String> = [
            "kind", "inputValue", "canonicalValue", "profile", "rulesVersion", "formatVersion",
            "engineVersion", "format", "checksum",
        ]
        #expect(expected.isSubset(of: Set(object.keys)))
        #expect(object["kind"] as? String == "siren")
        #expect(object["profile"] as? String == "compatible")
        #expect(object["rulesVersion"] as? String == "2026.08.17")
    }

    @Test("An absent country and an absent message key are omitted, not empty")
    func absenceIsOmitted() throws {
        let object = try encoded(
            BusinessIDEngine.default.validate(
                IdentifierInput(kind: "lei", value: "0000-0000-0000-0000-0098")
            )
        )
        #expect(object["countryCode"] == nil)
        let format = try #require(object["format"] as? [String: Any])
        #expect(format["messageKey"] == nil)
        #expect(format["status"] as? String == "valid")
        #expect(format["reasonCode"] as? String == "ok")
    }

    @Test("An identifier kind serializes as its bare string")
    func kindIsAString() throws {
        let data = try JSONEncoder().encode(IdentifierKind("siren"))
        #expect(String(decoding: data, as: UTF8.self) == "\"siren\"")
        #expect(try JSONDecoder().decode(IdentifierKind.self, from: data) == IdentifierKind("siren"))
    }

    @Test("An input round trips")
    func inputRoundTrip() throws {
        let input = IdentifierInput(kind: "vat", value: "BE 0123.456.749", countryCode: "BE")
        let data = try JSONEncoder().encode(input)
        #expect(try JSONDecoder().decode(IdentifierInput.self, from: data) == input)
    }
}
