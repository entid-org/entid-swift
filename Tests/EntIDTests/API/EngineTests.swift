import Testing

@testable import EntID

/// The public API and the normative pipeline.
///
/// Every literal value used here is quoted from a conformance case of
/// `spec/entid-conformance.jsonl`, named in the comment above it. None was
/// written from memory: an identifier that looks plausible and does not exist
/// is how seven wrong numbers reached a previous engine while its algorithms
/// were correct.
@Suite("Engine")
struct EngineTests {
    let engine = EntIDEngine.default

    // `siren-validate-format-050`.
    static let validSIREN = "012345674"
    // `siren-validate-format-invalid-051`.
    static let shortSIREN = "01234567"

    @Test("The engine reports the versions it was built from")
    func versions() {
        // The version itself is asserted against rules.lock in the packaging
        // suite; here what matters is that it is well formed and non empty.
        #expect(!engine.rulesVersion.isEmpty)
        #expect(engine.rulesVersion.split(separator: ".").count == 3)
        #expect(engine.formatVersion == 1)
        #expect(engine.engineVersion == EntID.engineVersion)

        let info = engine.rulesInfo()
        #expect(info.identifierCount == 94)
        #expect(info.countryCount == 37)
        #expect(info.kinds.count == 37)
        #expect(info.kinds.contains(IdentifierKind("siren")))
        #expect(engine.capabilities() == [1, 2, 3, 4, 5, 10, 11, 20, 21, 30, 31, 32, 33, 34, 35, 40, 41, 42])
    }

    @Test("The raw input is reported unchanged")
    func rawInputIsPreserved() {
        let raw = "  012 345-674  "
        let report = engine.validate(IdentifierInput(kind: "siren", value: raw))
        #expect(report.inputValue == raw)
        #expect(report.canonicalValue == Self.validSIREN)
    }

    @Test("An unknown kind is unsupported and runs no program")
    func unknownKind() {
        let report = engine.validate(IdentifierInput(kind: "no_such_kind", value: " X "))
        #expect(report.format.status == .unsupported)
        #expect(report.format.reasonCode == .unsupportedKind)
        #expect(report.checksum.status == .notRun)
        #expect(report.checksum.reasonCode == .notRunFormatUnsupported)
        // No program ran, so the value is reported verbatim.
        #expect(report.canonicalValue == " X ")
        #expect(report.kind == IdentifierKind("no_such_kind"))
    }

    @Test("A malformed kind token is unsupported rather than an error")
    func malformedKind() {
        for token in ["", "9siren", "SIREN!", String(repeating: "a", count: 65)] {
            let report = engine.validate(IdentifierInput(kind: IdentifierKind(token), value: "1"))
            #expect(report.format.reasonCode == .unsupportedKind, "\(token)")
        }
    }

    @Test("A kind token is trimmed and lower cased before it is looked up")
    func kindNormalization() {
        let report = engine.validate(IdentifierInput(kind: "  SIREN\t", value: Self.validSIREN))
        #expect(report.kind == IdentifierKind("siren"))
        #expect(report.format.status == .valid)
    }

    @Test("A kind alias resolves to the canonical kind")
    func kindAlias() {
        // `siren-canonicalize-alias-061`.
        let result = engine.canonicalize(IdentifierInput(kind: "fr_siren", value: Self.validSIREN))
        #expect(result.kind == IdentifierKind("siren"))
        #expect(result.status == .valid)
    }

    @Test("An input beyond 1024 UTF-8 bytes is refused without being processed")
    func inputTooLong() {
        let long = String(repeating: "1", count: 1025)
        let report = engine.validate(IdentifierInput(kind: "siren", value: long, countryCode: "FR"))
        // A safety bound is not by itself a business proof of invalidity.
        #expect(report.format.status == .unsupported)
        #expect(report.format.reasonCode == .inputTooLong)
        #expect(report.checksum.reasonCode == .notRunFormatUnsupported)
        #expect(report.canonicalValue == long)
        #expect(report.countryCode == "FR")
    }

    @Test("The bound counts UTF-8 bytes, not characters")
    func boundCountsBytes() {
        // 512 code points of two UTF-8 bytes each sit exactly on the bound.
        let onBound = String(repeating: "\u{00E9}", count: 512)
        #expect(onBound.utf8.count == 1024)
        #expect(
            engine.validate(IdentifierInput(kind: "siren", value: onBound)).format.reasonCode
                != .inputTooLong
        )
        let overBound = onBound + "\u{00E9}"
        #expect(
            engine.validate(IdentifierInput(kind: "siren", value: overBound)).format.reasonCode
                == .inputTooLong
        )
    }

    @Test("validate_format reports checksum not_run with not_requested")
    func validateFormatDoesNotRunChecksum() {
        let report = engine.validateFormat(IdentifierInput(kind: "siren", value: Self.validSIREN))
        #expect(report.format.status == .valid)
        #expect(report.checksum.status == .notRun)
        #expect(report.checksum.reasonCode == .notRequested)
    }

    @Test("validate_format keeps a format failure exactly as validate reports it")
    func validateFormatKeepsFailure() {
        let input = IdentifierInput(kind: "siren", value: Self.shortSIREN)
        let formatOnly = engine.validateFormat(input)
        let full = engine.validate(input)
        #expect(formatOnly.format == full.format)
        #expect(formatOnly.checksum == full.checksum)
        #expect(formatOnly.format.reasonCode == .invalidLength)
        #expect(formatOnly.format.messageKey == "fr.siren.length")
        #expect(formatOnly.checksum.reasonCode == .notRunFormatInvalid)
    }

    @Test("validate_checksum returns exactly what validate returns")
    func validateChecksumMatchesValidate() {
        for value in [Self.validSIREN, Self.shortSIREN, "", "abc", "012345670"] {
            let input = IdentifierInput(kind: "siren", value: value)
            #expect(engine.validateChecksum(input) == engine.validate(input), "\(value)")
        }
    }

    @Test("A checksum is never run on a format that did not validate")
    func checksumIsGuardedByFormat() {
        let report = engine.validate(IdentifierInput(kind: "siren", value: "not-a-siren"))
        #expect(report.format.status == .invalid)
        #expect(report.checksum.status == .notRun)
        #expect(report.checksum.reasonCode == .notRunFormatInvalid)
        // A step that did not run carries no key.
        #expect(report.checksum.messageKey == nil)
    }

    @Test("A result produced before any assertion carries no message key")
    func noKeyBeforeAnAssertion() {
        let reports = [
            engine.validate(IdentifierInput(kind: "no_such_kind", value: "X")),
            engine.validate(IdentifierInput(kind: "siren", value: String(repeating: "1", count: 2000))),
            engine.validateFormat(IdentifierInput(kind: "siren", value: Self.validSIREN)),
        ]
        for report in reports {
            #expect(report.format.messageKey == nil || report.format.status == .invalid)
            #expect(report.checksum.messageKey == nil)
        }
    }

    @Test("canonicalize runs neither format nor checksum and never reports not_run")
    func canonicalizeStopsEarly() {
        for value in [Self.validSIREN, Self.shortSIREN, "", "zzz"] {
            let result = engine.canonicalize(IdentifierInput(kind: "siren", value: value))
            #expect(result.status != .notRun, "\(value)")
        }
    }

    @Test("canonicalize and validate agree on the canonical value")
    func canonicalizationAgrees() {
        for value in ["  012 345-674 ", "01234567", "GB123", ""] {
            let input = IdentifierInput(kind: "siren", value: value)
            #expect(engine.canonicalize(input).canonicalValue == engine.validate(input).canonicalValue)
        }
    }

    @Test("A country contradicting a recognised prefix is the one dispatch failure that proves invalidity")
    func countryMismatch() {
        // `dispatch-canonicalize-country-mismatch-014`.
        let input = IdentifierInput(kind: "vat", value: "BE0123456749", countryCode: "FR")
        let report = engine.validate(input)
        #expect(report.format.status == .invalid)
        #expect(report.format.reasonCode == .countryMismatch)
        #expect(report.checksum.reasonCode == .notRunFormatInvalid)
        // The value already carries the pre-canonical form, and the country is
        // the normalized context.
        #expect(report.canonicalValue == "BE0123456749")
        #expect(report.countryCode == "FR")
    }

    @Test("A country with no target is reported with the value already pre-canonicalized")
    func unsupportedCountryKeepsPreCanonicalValue() {
        // `siren-canonicalize-unsupported-country-062`. Step 4 runs before the
        // country decision, so the value reported here is not the raw one.
        let result = engine.canonicalize(
            IdentifierInput(kind: "siren", value: "012 345 674", countryCode: "DE")
        )
        #expect(result.status == .unsupported)
        #expect(result.reasonCode == .unsupportedCountry)
        #expect(result.canonicalValue == "012345674")
        #expect(result.countryCode == "DE")
    }

    @Test("A malformed country token is unsupported and keeps the raw context")
    func malformedCountry() {
        let result = engine.canonicalize(
            IdentifierInput(kind: "siren", value: Self.validSIREN, countryCode: "Deutschland")
        )
        #expect(result.reasonCode == .unsupportedCountry)
        #expect(result.countryCode == "Deutschland")
    }

    @Test("An empty country token behaves like an absent context")
    func emptyCountryToken() {
        let absent = engine.validate(IdentifierInput(kind: "siren", value: Self.validSIREN))
        for token in ["", "  ", "\t"] {
            let given = engine.validate(
                IdentifierInput(kind: "siren", value: Self.validSIREN, countryCode: token)
            )
            #expect(given.format == absent.format, "\(token.debugDescription)")
            #expect(given.countryCode == absent.countryCode)
        }
    }

    @Test("The country of a target is its ISO code even when its prefix differs")
    func isoCountryNotBusinessPrefix() {
        // `vat-gr-canonicalize-040`: prefix EL, country GR.
        let result = engine.canonicalize(IdentifierInput(kind: "vat", value: "gr 012345670"))
        #expect(result.canonicalValue == "EL012345670")
        #expect(result.countryCode == "GR")
    }

    @Test("A GLOBAL target keeps a well formed country context without routing on it")
    func globalTargetKeepsContext() {
        // `lei-canonicalize-020` is a GLOBAL definition.
        let withContext = engine.canonicalize(
            IdentifierInput(kind: "lei", value: "0000-0000-0000-0000-0098", countryCode: "fr")
        )
        #expect(withContext.status == .valid)
        #expect(withContext.canonicalValue == "00000000000000000098")
        #expect(withContext.countryCode == "FR")

        let without = engine.canonicalize(
            IdentifierInput(kind: "lei", value: "0000-0000-0000-0000-0098")
        )
        #expect(without.countryCode == nil)
        #expect(without.canonicalValue == withContext.canonicalValue)
    }

    @Test("Passing the default profile explicitly is the same as the definition's default")
    func explicitDefaultProfile() {
        let input = IdentifierInput(kind: "siren", value: Self.validSIREN)
        let silent = engine.validate(input)
        let explicit = engine.validate(input, options: ValidationOptions(profile: .compatible))
        #expect(silent.profile == .compatible)
        #expect(explicit.profile == .compatible)
        #expect(silent.format == explicit.format)
    }

    @Test("strict_current never reports valid where compatible reported invalid")
    func strictNeverWidens() {
        // strict_current is opt-in and accepts a subset; it can refuse where
        // compatible accepts, never the other way round.
        for value in ["012345674", "01234567", "FR09012345674", "BE0123456749", "abc"] {
            for kind in ["siren", "vat"] {
                let input = IdentifierInput(kind: IdentifierKind(kind), value: value)
                let compatible = engine.validate(input, options: .init(profile: .compatible))
                let strict = engine.validate(input, options: .init(profile: .strictCurrent))
                if compatible.format.status == .invalid {
                    #expect(strict.format.status != .valid, "\(kind) \(value)")
                }
            }
        }
    }

    @Test("The report offers no ambiguous overall verdict")
    func namedVerdicts() {
        // `cegjegyzekszam-hu-valid-001`: a format that validates and a checksum
        // its authority does not publish. Neither fully validated nor invalid.
        let report = engine.validate(IdentifierInput(kind: "cegjegyzekszam", value: "0123456789"))
        #expect(report.isFormatValid)
        #expect(!report.isChecksumValid)
        #expect(!report.isFullyValidated)
        #expect(!report.isInvalid)
        #expect(report.checksum.status == .unsupported)
        #expect(report.checksum.reasonCode == .checksumNotPublished)
    }

    @Test("An unpublished checksum never becomes invalid")
    func unpublishedChecksumStaysUnsupported() {
        for value in ["0123456789", "9999999999", "0000000000"] {
            let report = engine.validate(IdentifierInput(kind: "cegjegyzekszam", value: value))
            guard report.isFormatValid else { continue }
            #expect(report.checksum.status != .invalid, "\(value)")
        }
    }
}
