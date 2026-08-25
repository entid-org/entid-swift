package import EntIDWire
import Testing

import struct Foundation.Data

@testable import EntIDGenerator

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

    // MARK: A WHEN branch nothing references

    /// `ir.md` section 3.6 on `CHECKSUM_OP_KIND_WHEN`: "It is accepted only as a
    /// direct operand of `CHOOSE`; its non applicable state is never observable
    /// elsewhere." Check 16 carries it.
    ///
    /// A `WHEN` no node reads is not a direct operand of anything, so it is
    /// refused. The reference loader enforced the rule by looking at each node's
    /// *parents*, and a node with no parent has none to look at — section 2
    /// permits an unreachable node, so a dead `WHEN` passed there. The Kotlin
    /// engine read the rule as written and refused it.
    ///
    /// Three shapes, because one of them alone proves nothing: the dead branch
    /// must be refused, the legitimate one must still be accepted, and a program
    /// rooted at a `WHEN` keeps its own rule and its own message — `root_node`
    /// is a reference, so that program has a parent of a kind.
    static func withChecksumProgram(
        _ bundle: inout BundleBuilder.Bundle,
        nodes: [Libbusinessid_Ir_V1_Node],
        root: UInt32
    ) {
        bundle.programs.append(BundleBuilder.program(id: 4, kind: .checksum, nodes: nodes, root: root))
        bundle.identifiers[0].checksumProgram = 4
        bundle.identifiers[0].clearAbsentChecksumReason()
        bundle.requiredFeatureIds = [1, 2, 3, 5, 20, 21, 30, 31, 40]
    }

    /// The control: the same bundle with the `WHEN` where it belongs.
    @Test("A WHEN read by a CHOOSE is accepted")
    func whenInsideChooseIsAccepted() throws {
        let outcome = try load {
            Self.withChecksumProgram(
                &$0,
                nodes: [
                    BundleBuilder.string(.subject),
                    BundleBuilder.checksum(.luhn, inputs: [0]),
                    BundleBuilder.predicate(.isEmpty, inputs: [0]),
                    BundleBuilder.checksum(.when, inputs: [2, 1]),
                    BundleBuilder.checksum(.choose, inputs: [3, 1]),
                ],
                root: 4
            )
        }
        if case .failure(let error) = outcome { Issue.record("\(error)") }
    }

    @Test("A WHEN branch nothing references is refused")
    func deadWhenIsRefused() throws {
        let outcome = try load {
            Self.withChecksumProgram(
                &$0,
                nodes: [
                    BundleBuilder.string(.subject),
                    BundleBuilder.checksum(.luhn, inputs: [0]),
                    BundleBuilder.predicate(.isEmpty, inputs: [0]),
                    // Read by nothing: not the root, not an operand.
                    BundleBuilder.checksum(.when, inputs: [2, 1]),
                ],
                root: 1
            )
        }
        guard case .failure(let error) = outcome else {
            Issue.record("a WHEN branch no node reads was accepted")
            return
        }
        #expect(error.engineErrorName == "invalid_ruleset")
        #expect(error.reason.contains("WHEN branch outside a CHOOSE"))
    }

    @Test("A checksum program rooted at a WHEN keeps its own message")
    func whenAtTheRootIsRefusedByTheRootRule() throws {
        let outcome = try load {
            Self.withChecksumProgram(
                &$0,
                nodes: [
                    BundleBuilder.string(.subject),
                    BundleBuilder.checksum(.luhn, inputs: [0]),
                    BundleBuilder.predicate(.isEmpty, inputs: [0]),
                    BundleBuilder.checksum(.when, inputs: [2, 1]),
                ],
                root: 3
            )
        }
        guard case .failure(let error) = outcome else {
            Issue.record("a checksum program rooted at a WHEN was accepted")
            return
        }
        // The root rule, not the operand rule: a reader has to be able to tell
        // which of the two was broken.
        #expect(error.reason.contains("never roots at a WHEN branch"))
    }

    // MARK: The order of section 10

    /// `ir.md` section 10 numbers its checks and says "in this order". Two
    /// engines answered differently on the same bytes because one ran the
    /// operation categories in the per-node pass, ahead of the arithmetic
    /// bounds at check 13, while the rule belongs to check 16. Since
    /// `2026.08.26` check 16 names the categories explicitly, so which check
    /// answers is now a stated property rather than an accident of structure.
    ///
    /// The node below carries both faults at once, exactly as the old
    /// `loader-left-pad-length-026` fixture did: a `LEFT_PAD` — a
    /// canonicalization operation with no place in a format program, check 16 —
    /// whose `length` is one past the slice bound, check 13. Thirteen comes
    /// first, so the length is what a conformant loader reports.
    @Test("A node breaking both check 13 and check 16 is refused by thirteen")
    func arithmeticBoundsPrecedeTheShape() throws {
        let outcome = try load {
            $0.programs[2].nodes.insert(
                BundleBuilder.canonical(.leftPad) { operation in
                    operation.text = "0"
                    operation.length = 4097
                },
                at: 0
            )
            // Every operand index above the insertion shifts by one.
            for index in $0.programs[2].nodes.indices where index > 0 {
                $0.programs[2].nodes[index].inputNodes = $0.programs[2].nodes[index].inputNodes.map { $0 + 1 }
            }
            $0.programs[2].rootNode += 1
        }

        guard case .failure(let error) = outcome else {
            Issue.record("a bundle carrying both faults was accepted")
            return
        }
        #expect(error.engineErrorName == "invalid_ruleset")
        #expect(
            error.reason.contains("length 4097 is outside"),
            Comment(rawValue: "check 13 must answer before check 16, got: \(error.reason)")
        )
        #expect(!error.reason.contains("has no place in a format program"))
    }

    /// The same node with a legal bound, so the category is what is left to
    /// object to. Without this, the test above would pass against a loader that
    /// had no category rule at all.
    @Test("With the bound repaired, check 16 refuses the same node for its category")
    func theShapeStillRefusesTheCategory() throws {
        let outcome = try load {
            $0.programs[2].nodes.insert(
                BundleBuilder.canonical(.leftPad) { operation in
                    operation.text = "0"
                    operation.length = 4096
                },
                at: 0
            )
            for index in $0.programs[2].nodes.indices where index > 0 {
                $0.programs[2].nodes[index].inputNodes = $0.programs[2].nodes[index].inputNodes.map { $0 + 1 }
            }
            $0.programs[2].rootNode += 1
        }

        guard case .failure(let error) = outcome else {
            Issue.record("a canonicalization step in a format program was accepted")
            return
        }
        #expect(error.reason.contains("has no place in a format program"))
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
