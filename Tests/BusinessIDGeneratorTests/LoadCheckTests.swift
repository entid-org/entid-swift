package import BusinessIDWire
import Testing

import struct Foundation.Data

@testable import BusinessIDGenerator

/// One property per case, on the smallest ruleset that carries it.
///
/// The corpus covers thirty four hostile bundles; these cover the checks it
/// does not reach, and each one starts from an accepted bundle so that the
/// single mutation is what the test is about.
@Suite("Load checks")
struct LoadCheckTests {
    private func load(
        _ mutate: (inout BundleBuilder.Bundle) -> Void = { _ in }
    ) throws -> Result<
        LoadedBundle, LoadError
    > {
        var bundle = BundleBuilder.minimal()
        mutate(&bundle)
        let bytes = try BundleBuilder.bytes(bundle)
        do {
            return .success(try RuleBundleLoader.load(bytes))
        } catch {
            return .failure(error)
        }
    }

    private func expectRefused(
        _ expected: LoadError,
        _ comment: Comment,
        _ mutate: (inout BundleBuilder.Bundle) -> Void
    ) throws {
        switch try load(mutate) {
        case .success:
            Issue.record(comment)
        case .failure(let error):
            #expect(error.engineErrorName == expected.engineErrorName, comment)
        }
    }

    @Test("The minimal bundle is accepted, so a refusal below is the mutation")
    func minimalIsAccepted() throws {
        let outcome = try load()
        guard case .success(let bundle) = outcome else {
            Issue.record("\(outcome)")
            return
        }
        #expect(bundle.definitions.count == 1)
        #expect(bundle.dispatchers.count == 1)
        #expect(bundle.programs.count == 3)
    }

    // MARK: Header

    @Test("An unsupported format version closes the execution")
    func unsupportedFormatVersion() throws {
        try expectRefused(.incompatibleRuleset(""), "a later format version must be a version gap") {
            $0.formatVersion = 2
        }
    }

    @Test("A single unknown capability id closes the execution")
    func unknownCapability() throws {
        try expectRefused(.incompatibleRuleset(""), "an unknown capability must be a version gap") {
            $0.requiredFeatureIds.append(9999)
        }
    }

    @Test("Capability ids out of order are a structural violation, not a version gap")
    func unsortedCapabilities() throws {
        try expectRefused(.invalidRuleset(""), "required_feature_ids must be strictly ascending") {
            $0.requiredFeatureIds = [3, 1, 2, 5, 20, 21, 30, 40]
        }
    }

    @Test("A repeated capability id is refused")
    func repeatedCapability() throws {
        try expectRefused(.invalidRuleset(""), "two equal sort keys are a duplicate") {
            $0.requiredFeatureIds = [1, 1, 2, 3, 5, 20, 21, 30, 40]
        }
    }

    @Test("A digest of the wrong length is refused")
    func shortDigest() throws {
        try expectRefused(.invalidRuleset(""), "source_digest is exactly 32 bytes") {
            $0.sourceDigest = Data(repeating: 0, count: 31)
        }
    }

    @Test("A rules version holding a control character is refused")
    func rulesVersionShape() throws {
        try expectRefused(.invalidRuleset(""), "the value reaches generated sources and logs") {
            $0.rulesVersion = "2026.08.17\u{0}"
        }
    }

    @Test("A rules version beyond sixty four bytes is refused")
    func rulesVersionLength() throws {
        try expectRefused(.invalidRuleset(""), "rules_version is at most 64 bytes") {
            $0.rulesVersion = String(repeating: "9", count: 65)
        }
    }

    // MARK: Programs

    @Test("Programs out of ascending id order are refused")
    func unsortedPrograms() throws {
        try expectRefused(.invalidRuleset(""), "programs are sorted by ascending id") {
            $0.programs.reverse()
        }
    }

    @Test("A program carrying id zero is refused")
    func zeroProgramID() throws {
        try expectRefused(.invalidRuleset(""), "program ids are non zero") {
            $0.programs[0].id = 0
        }
    }

    @Test("A capture naming a node outside the program is refused")
    func captureOutOfRange() throws {
        try expectRefused(.invalidRuleset(""), "capture nodes sit inside the program") {
            var capture = Libbusinessid_Ir_V1_Capture()
            capture.name = "part"
            capture.node = 99
            $0.programs[2].captures = [capture]
        }
    }

    @Test("A canonicalization program declaring a capture is refused")
    func canonicalizationCapture() throws {
        try expectRefused(.invalidRuleset(""), "a canonicalization program declares no capture") {
            var capture = Libbusinessid_Ir_V1_Capture()
            capture.name = "part"
            capture.node = 0
            $0.programs[0].captures = [capture]
        }
    }

    @Test("A subject node whose subtree reads subject() is refused")
    func selfReferentialSubject() throws {
        // `subject()` would then be defined in terms of itself, and an engine
        // that emits the subject node as a function would recur forever.
        try expectRefused(.invalidRuleset(""), "a subject node cannot be defined by itself") {
            $0.programs[2].subjectNode = 0
            $0.requiredFeatureIds = [1, 2, 3, 5, 11, 20, 21, 30, 40]
        }
    }

    @Test("A subject node that does not read subject() is accepted")
    func wellFoundedSubject() throws {
        let outcome = try load {
            $0.programs[2].nodes.insert(BundleBuilder.string(.value), at: 0)
            $0.programs[2].nodes[1].inputNodes = []
            // Every later node shifted by one.
            $0.programs[2].nodes[2].inputNodes = [1]
            $0.programs[2].nodes[3].inputNodes = [2]
            $0.programs[2].nodes[4].inputNodes = [3]
            $0.programs[2].nodes[5].inputNodes = [4]
            $0.programs[2].rootNode = 5
            $0.programs[2].subjectNode = 0
            $0.requiredFeatureIds = [1, 2, 3, 5, 11, 20, 21, 30, 40]
        }
        if case .failure(let error) = outcome { Issue.record("\(error)") }
    }

    @Test("subject() has no place in a canonicalization program")
    func subjectInCanonicalization() throws {
        try expectRefused(.invalidRuleset(""), "subject() is forbidden there") {
            $0.programs[1].nodes = [
                BundleBuilder.string(.subject),
                BundleBuilder.predicate(.isEmpty, inputs: [0]),
                BundleBuilder.canonical(.when, inputs: [1, 2]),
                BundleBuilder.canonical(.uppercaseAscii),
                BundleBuilder.canonical(.sequence, inputs: [3]),
            ]
            $0.programs[1].rootNode = 4
        }
    }

    @Test("A pre-canonicalization program is restricted to its five steps")
    func preCanonicalizationRestriction() throws {
        try expectRefused(.invalidRuleset(""), "it can never add, replace or interpret a prefix") {
            $0.programs[0].nodes = [
                BundleBuilder.canonical(.prepend) { $0.text = "X" },
                BundleBuilder.canonical(.sequence, inputs: [0]),
            ]
        }
    }

    @Test("prepend_country_if_missing has no place in a GLOBAL canonicalizer")
    func prependCountryInGlobalCanonicalizer() throws {
        try expectRefused(.invalidRuleset(""), "a GLOBAL target has no country to prepend") {
            $0.programs[1].nodes = [
                BundleBuilder.canonical(.prependCountryIfMissing),
                BundleBuilder.canonical(.sequence, inputs: [0]),
            ]
            $0.requiredFeatureIds = [1, 2, 3, 5, 20, 21, 30, 40]
        }
    }

    @Test("A format program rooted anywhere but an assertion sequence is refused")
    func formatRoot() throws {
        try expectRefused(.invalidRuleset(""), "a format program roots at SEQUENCE") {
            $0.programs[2].rootNode = 3
        }
    }

    // MARK: Arithmetic

    @Test("An accepted length list out of order is refused")
    func unsortedLengths() throws {
        try expectRefused(.invalidRuleset(""), "lengths are ascending and deduplicated") {
            $0.programs[2].nodes[1] = BundleBuilder.predicate(.lengthIn, inputs: [0]) {
                $0.lengths = [9, 3]
            }
        }
    }

    @Test("A length range whose minimum exceeds its maximum is refused")
    func invertedLengthRange() throws {
        try expectRefused(.invalidRuleset(""), "the compiler requires min <= max") {
            $0.programs[2].nodes[1] = BundleBuilder.predicate(.lengthBetween, inputs: [0]) {
                $0.minLength = 9
                $0.maxLength = 3
            }
        }
    }

    @Test("An index beyond the slice bound is refused")
    func indexOutOfBound() throws {
        try expectRefused(.invalidRuleset(""), "an index lies in 0...4096") {
            $0.programs[2].nodes[1] = BundleBuilder.predicate(.charAtIn, inputs: [0]) {
                $0.index = 4097
                $0.text = "0"
            }
        }
    }

    @Test("A profile the V1 registry does not name is refused")
    func unknownProfileName() throws {
        try expectRefused(.invalidRuleset(""), "profiles are compatible and strict_current") {
            $0.programs[2].nodes[1] = BundleBuilder.predicate(.profileIs) { $0.text = "lenient" }
            $0.programs[2].nodes[1].inputNodes = []
        }
    }

    @Test("A reason code that proves nothing cannot be required")
    func forbiddenRequireReason() throws {
        try expectRefused(.invalidRuleset(""), "REQUIRE proves an invalidity or nothing") {
            $0.programs[2].nodes[3] = BundleBuilder.require(2, reason: .unsupportedChecksum)
        }
    }

    @Test("A message key present but empty is refused")
    func emptyMessageKey() throws {
        try expectRefused(.invalidRuleset(""), "an empty key cannot be told from an absent one") {
            $0.programs[2].nodes[3].assertionOperation.messageKey = ""
        }
    }

    // MARK: Definitions and dispatch

    @Test("A definition declaring both a checksum program and an absence reason is refused")
    func bothChecksumAndAbsence() throws {
        try expectRefused(.invalidRuleset(""), "exactly one of the two") {
            $0.identifiers[0].checksumProgram = 3
        }
    }

    @Test("A definition declaring neither is refused")
    func neitherChecksumNorAbsence() throws {
        try expectRefused(.invalidRuleset(""), "exactly one of the two") {
            $0.identifiers[0].clearAbsentChecksumReason()
        }
    }

    @Test("A definition citing no source is refused")
    func definitionWithoutSource() throws {
        try expectRefused(.invalidRuleset(""), "a rule able to reject carries a source") {
            $0.identifiers[0].sources = []
        }
    }

    @Test("Sources out of ascending id order are refused")
    func unsortedSources() throws {
        try expectRefused(.invalidRuleset(""), "sources are sorted by the UTF-8 bytes of their id") {
            var second = $0.identifiers[0].sources[0]
            second.id = "a-first-source"
            $0.identifiers[0].sources.append(second)
        }
    }

    @Test("A source tier outside the enumeration is refused")
    func unknownSourceTier() throws {
        try expectRefused(.invalidRuleset(""), "two engines would read the same source differently") {
            $0.identifiers[0].sources[0].tier = .UNRECOGNIZED(7)
        }
    }

    @Test("A stated tier requires PROVENANCE_TIER_V1")
    func statedTierRequiresCapability() throws {
        try expectRefused(.invalidRuleset(""), "only a stated tier requires it, but it does require it") {
            $0.identifiers[0].sources[0].tier = .primary
        }
    }

    @Test("A source stating no tier does not require PROVENANCE_TIER_V1")
    func unstatedTierRequiresNothing() throws {
        // `tier` is not `optional`, so an omitted field and UNSPECIFIED are the
        // same bytes: UNSPECIFIED means the source states no tier.
        let outcome = try load { $0.identifiers[0].sources[0].tier = .unspecified }
        if case .failure(let error) = outcome { Issue.record("\(error)") }
    }

    @Test("The literal GLOBAL is not a country code")
    func literalGlobalCountry() throws {
        try expectRefused(.invalidRuleset(""), "absence means GLOBAL; the literal does not") {
            $0.identifiers[0].countryCode = "GLOBAL"
            $0.dispatchers[0].targets[0].countryCode = "GLOBAL"
        }
    }

    @Test("A definition no dispatch target references is refused")
    func orphanDefinition() throws {
        try expectRefused(.invalidRuleset(""), "every definition is referenced exactly once") {
            var second = $0.identifiers[0]
            second.id = 2
            second.countryCode = "FR"
            $0.identifiers.append(second)
        }
    }

    @Test("A kind alias claimed twice is refused")
    func duplicateKindAlias() throws {
        try expectRefused(.invalidRuleset(""), "kinds and aliases share one space") {
            $0.dispatchers[0].kindAliases = ["test"]
        }
    }

    @Test("A country alias mapping a token to itself is refused")
    func selfMappingCountryAlias() throws {
        try expectRefused(.invalidRuleset(""), "an alias that maps to itself says nothing") {
            $0.dispatchers[0].targets[0].countryCode = "FR"
            $0.identifiers[0].countryCode = "FR"
            var alias = Libbusinessid_Ir_V1_CountryAlias()
            alias.alias = "UK"
            alias.countryCode = "UK"
            $0.dispatchers[0].countryAliases = [alias]
            $0.requiredFeatureIds = [1, 2, 3, 5, 20, 21, 30, 40]
        }
    }

    @Test("A country alias shadowing a target is refused")
    func shadowingCountryAlias() throws {
        try expectRefused(.invalidRuleset(""), "the alias would never be reached") {
            $0.dispatchers[0].targets[0].countryCode = "FR"
            $0.identifiers[0].countryCode = "FR"
            var alias = Libbusinessid_Ir_V1_CountryAlias()
            alias.alias = "FR"
            alias.countryCode = "BE"
            $0.dispatchers[0].countryAliases = [alias]
            $0.requiredFeatureIds = [1, 2, 3, 5, 20, 21, 30, 40]
        }
    }

    @Test("A GLOBAL target declaring a prefix is refused")
    func globalTargetWithPrefix() throws {
        try expectRefused(.invalidRuleset(""), "a GLOBAL target has no prefix") {
            $0.dispatchers[0].targets[0].acceptedPrefixes = ["XX"]
        }
    }

    @Test("A GLOBAL target mixed with a country target is refused")
    func globalTargetNotAlone() throws {
        try expectRefused(.invalidRuleset(""), "a GLOBAL target is alone") {
            var second = $0.identifiers[0]
            second.id = 2
            second.countryCode = "FR"
            $0.identifiers.append(second)
            var target = Libbusinessid_Ir_V1_DispatchTarget()
            target.countryCode = "FR"
            target.identifierDefinitionID = 2
            $0.dispatchers[0].targets.append(target)
            $0.requiredFeatureIds = [1, 2, 3, 5, 20, 21, 30, 40]
        }
    }

    @Test("A call typed against the wrong program family is refused")
    func mistypedCall() throws {
        try expectRefused(.invalidRuleset(""), "a format call runs a format program") {
            $0.programs[2].nodes.insert(BundleBuilder.call(.checksum, program: 3, input: 0), at: 4)
            $0.programs[2].nodes[5].inputNodes = [3, 4]
            $0.programs[2].rootNode = 5
            $0.requiredFeatureIds = [1, 2, 3, 5, 11, 20, 21, 30, 40]
        }
    }

    @Test("A self recursive call graph is refused")
    func selfCall() throws {
        try expectRefused(.invalidRuleset(""), "the call graph is acyclic") {
            $0.programs[2].nodes.insert(BundleBuilder.call(.format, program: 3, input: 0), at: 4)
            $0.programs[2].nodes[5].inputNodes = [3, 4]
            $0.programs[2].rootNode = 5
            $0.requiredFeatureIds = [1, 2, 3, 5, 11, 20, 21, 30, 40]
        }
    }

    @Test("A capability used without being declared is refused")
    func undeclaredCapability() throws {
        try expectRefused(.invalidRuleset(""), "an omission must not read as permission") {
            $0.requiredFeatureIds = [1, 2, 3, 5, 20, 21, 30]
        }
    }

    @Test("A bundle beyond sixteen mebibytes is refused before decoding")
    func oversizedBundle() throws {
        let bytes = [UInt8](repeating: 0, count: Limits.maximumBundleBytes + 1)
        #expect(throws: LoadError.self) { try RuleBundleLoader.load(bytes) }
    }
}
