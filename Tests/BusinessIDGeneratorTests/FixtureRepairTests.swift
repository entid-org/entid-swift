package import BusinessIDWire
import Testing

import struct Foundation.Data

@testable import BusinessIDGenerator

/// The property every hostile fixture has to have: repair the defect its name
/// carries, and the bundle loads.
///
/// **Repair, not erase.** Deleting the construct that carries the defect
/// removes the defect and everything else that construct could be wrong about
/// at the same time, so the test passes against a fixture carrying two — which
/// is exactly the fixture it was written to accuse. This engine had that flaw:
/// its check on `loader-subject-node-circular-037` cleared `subject_node`
/// instead of pointing it somewhere well founded, and would have kept passing
/// while the fixture was refused for a capability it also omitted.
///
/// The property cuts both ways, which is why it is worth running on every
/// fixture that admits a repair:
///
/// - a repaired fixture that is still refused means either the fixture carries
///   a second defect, or this loader is too strict — and refusing a valid
///   ruleset is the failure this project takes most seriously;
/// - an unrepaired fixture that is accepted means the check it names is
///   missing.
@Suite("Loader fixture repairs")
struct FixtureRepairTests {
    typealias Bundle = Libbusinessid_Ir_V1_RuleBundle

    /// One fixture, and the smallest change that fixes what its name says is
    /// wrong with it.
    struct Repair: Sendable, CustomTestStringConvertible {
        let caseID: String
        /// What the repair does, for the failure message.
        let what: String
        let apply: @Sendable (inout Bundle) -> Void

        var testDescription: String { caseID }
    }

    /// The rules version the demo bundle carries, restored where a fixture
    /// broke it.
    static let demoRulesVersion = "2026.08.0"

    static let repairs: [Repair] = [
        Repair(caseID: "loader-unsupported-format-version-004", what: "restore format_version 1") {
            $0.formatVersion = 1
        },
        Repair(caseID: "loader-unknown-feature-005", what: "drop the unknown capability") {
            $0.requiredFeatureIds.removeAll { !Capability.known.contains($0) }
        },
        Repair(caseID: "loader-unknown-field-root-003", what: "drop the unknown field") {
            $0.unknownFields = .init()
        },
        Repair(caseID: "loader-empty-rules-version-008", what: "restore a business version") {
            $0.rulesVersion = demoRulesVersion
        },
        Repair(caseID: "loader-rules-version-shape-029", what: "drop the control character") {
            $0.rulesVersion = demoRulesVersion
        },
        Repair(caseID: "loader-short-digest-007", what: "restore a thirty two byte digest") {
            $0.sourceDigest = Data(repeating: 0, count: 32)
        },
        Repair(caseID: "loader-source-tier-unknown-035", what: "state a known tier") {
            for index in $0.identifiers.indices {
                for source in $0.identifiers[index].sources.indices {
                    $0.identifiers[index].sources[source].tier = .primary
                }
            }
        },
        Repair(caseID: "loader-empty-message-key-027", what: "restore the message key") {
            mutateAssertions(&$0) { operation in
                guard operation.hasMessageKey, operation.messageKey.isEmpty else { return }
                operation.messageKey = "demo.length"
            }
        },
        Repair(caseID: "loader-forbidden-reason-code-018", what: "require a proving reason") {
            mutateAssertions(&$0) { operation in
                guard operation.kind == .require, operation.reasonCode == .unsupportedKind else { return }
                operation.reasonCode = .invalidLength
            }
        },
        Repair(caseID: "loader-node-forward-reference-010", what: "read a lower node") {
            mutateProgram(&$0, id: 2) { program in
                program.nodes[1].inputNodes = [0]
            }
        },
        Repair(caseID: "loader-node-out-of-range-011", what: "root at the assertion sequence") {
            mutateProgram(&$0, id: 2) { program in
                program.rootNode = 5
            }
        },
        Repair(
            caseID: "loader-subject-node-circular-037",
            what: "build the subject from value(), not from itself"
        ) {
            // The subject node stays declared. Repairing it means giving it
            // something to be built from that is not the subject it defines.
            mutateProgram(&$0, id: 2) { program in
                var value = Libbusinessid_Ir_V1_StringOperation()
                value.kind = .value
                var node = Libbusinessid_Ir_V1_Node()
                node.outputType = .string
                node.stringOperation = value
                program.nodes[Int(program.subjectNode)] = node
            }
        },
        Repair(caseID: "loader-global-target-with-prefix-023", what: "unprefix GLOBAL") {
            for dispatcher in $0.dispatchers.indices {
                for target in $0.dispatchers[dispatcher].targets.indices
                where !$0.dispatchers[dispatcher].targets[target].hasCountryCode {
                    $0.dispatchers[dispatcher].targets[target].acceptedPrefixes = []
                }
            }
        },
        Repair(caseID: "loader-modulus-out-of-range-021", what: "use a modulus in range") {
            mutateIntegers(&$0) { operation in
                guard operation.kind == .modDigits else { return }
                operation.modulus = 97
            }
        },
        Repair(caseID: "loader-stray-parameter-019", what: "drop the stray parameter") {
            mutatePredicates(&$0) { operation in
                guard operation.kind == .asciiDigits else { return }
                operation.clearText()
            }
        },
        Repair(caseID: "loader-unspecified-enum-013", what: "state the program kind") {
            for index in $0.programs.indices where $0.programs[index].kind == .unspecified {
                $0.programs[index].kind = .canonicalization
            }
        },
        Repair(caseID: "loader-missing-operation-009", what: "restore the lost operation") {
            for program in $0.programs.indices {
                for node in $0.programs[program].nodes.indices
                where $0.programs[program].nodes[node].operation == nil {
                    var predicate = Libbusinessid_Ir_V1_PredicateOperation()
                    predicate.kind = .lengthEq
                    predicate.length = 4
                    $0.programs[program].nodes[node].predicateOperation = predicate
                }
            }
        },
    ]

    // MARK: - Locating a construct by what it is, never by where it sits

    static func mutateProgram(
        _ bundle: inout Bundle,
        id: UInt32,
        _ body: (inout Libbusinessid_Ir_V1_Program) -> Void
    ) {
        for index in bundle.programs.indices where bundle.programs[index].id == id {
            body(&bundle.programs[index])
        }
    }

    static func mutateAssertions(
        _ bundle: inout Bundle,
        _ body: (inout Libbusinessid_Ir_V1_AssertionOperation) -> Void
    ) {
        forEachNode(&bundle) { node in
            guard case .assertionOperation(var operation) = node.operation else { return }
            body(&operation)
            node.assertionOperation = operation
        }
    }

    static func mutatePredicates(
        _ bundle: inout Bundle,
        _ body: (inout Libbusinessid_Ir_V1_PredicateOperation) -> Void
    ) {
        forEachNode(&bundle) { node in
            guard case .predicateOperation(var operation) = node.operation else { return }
            body(&operation)
            node.predicateOperation = operation
        }
    }

    static func mutateIntegers(
        _ bundle: inout Bundle,
        _ body: (inout Libbusinessid_Ir_V1_IntegerOperation) -> Void
    ) {
        forEachNode(&bundle) { node in
            guard case .integerOperation(var operation) = node.operation else { return }
            body(&operation)
            node.integerOperation = operation
        }
    }

    static func mutateCanonicalizations(
        _ bundle: inout Bundle,
        _ body: (inout Libbusinessid_Ir_V1_CanonicalizationOperation) -> Void
    ) {
        forEachNode(&bundle) { node in
            guard case .canonicalizationOperation(var operation) = node.operation else { return }
            body(&operation)
            node.canonicalizationOperation = operation
        }
    }

    static func forEachNode(_ bundle: inout Bundle, _ body: (inout Libbusinessid_Ir_V1_Node) -> Void) {
        for program in bundle.programs.indices {
            for node in bundle.programs[program].nodes.indices {
                body(&bundle.programs[program].nodes[node])
            }
        }
    }

    // MARK: - The property

    static func payload(_ caseID: String) throws -> Bundle {
        let testCase = try SpecCorpus.loaderCases().first { $0.id == caseID }
        return try Bundle(serializedBytes: [UInt8](try #require(testCase).rulesPayload))
    }

    static func outcome(_ bundle: Bundle) throws -> LoadError? {
        let bytes: [UInt8] = try bundle.serializedBytes()
        do {
            _ = try RuleBundleLoader.load(bytes)
            return nil
        } catch {
            return error
        }
    }

    @Test("Repairing the named defect makes the fixture load", arguments: repairs)
    func repairedFixtureLoads(_ repair: Repair) throws {
        var bundle = try Self.payload(repair.caseID)
        repair.apply(&bundle)
        if let error = try Self.outcome(bundle) {
            Issue.record(
                Comment(
                    rawValue: """
                        \(repair.caseID) is still refused after the repair "\(repair.what)":
                            \(error)
                        Either the fixture carries a second defect, or this loader is too strict.
                        """
                )
            )
        }
    }

    @Test("The fixture as shipped is refused", arguments: repairs)
    func unrepairedFixtureIsRefused(_ repair: Repair) throws {
        let error = try Self.outcome(try Self.payload(repair.caseID))
        #expect(error != nil, Comment(rawValue: "\(repair.caseID) was accepted unrepaired"))
        #expect(error?.engineErrorName != nil)
    }

    /// `loader-left-pad-length-026` does not have the property, and this states
    /// what was measured rather than leaving it to a comment.
    ///
    /// The fixture puts a `LEFT_PAD` canonicalization node inside the *format*
    /// program and roots the format program at it. That is two check 16
    /// violations on top of the length its name is about, so an engine that
    /// never implemented the slice bound on `left_pad` refuses the fixture
    /// anyway and passes the case for the wrong reason.
    ///
    /// It cannot be repaired in place either: the demo bundle's only
    /// canonicalization program is also the dispatcher's pre-canonicalizer,
    /// which is restricted to five steps that do not include `LEFT_PAD`, so the
    /// step has no legal home in this bundle. Reported upstream.
    ///
    /// This test fails the day the fixture is fixed, which is the signal to
    /// move it into the table above.
    @Test("The left_pad fixture is refused for its length, and for two other things")
    func leftPadFixtureCarriesASecondDefect() throws {
        let base = try Self.payload("loader-left-pad-length-026")

        // As shipped, the named defect is what this loader reports.
        let shipped = try #require(try Self.outcome(base))
        #expect(shipped.reason.contains("length 4097 is outside"))

        // Repair only that, and the bundle is still refused — by the program
        // shape, which an engine without any `left_pad` bound also reaches.
        var repaired = base
        Self.mutateCanonicalizations(&repaired) { operation in
            guard operation.kind == .leftPad else { return }
            operation.length = 4096
        }
        let afterRepair = try #require(try Self.outcome(repaired))
        #expect(afterRepair.reason.contains("format program roots at an assertion SEQUENCE"))
    }

    @Test("Every fixture that admits a repair is covered, and the rest are named")
    func coverage() throws {
        let repaired = Set(Self.repairs.map(\.caseID))
        let all = Set(try SpecCorpus.loaderCases().map(\.id))

        // A fixture with no repair below is one whose defect cannot be undone
        // by changing a field: the bytes do not decode, or the shape itself is
        // the defect. Naming them is what keeps this list from quietly
        // shrinking.
        let noRepairDefinable: Set<String> = [
            // The bytes are not a message; there is nothing to repair.
            "loader-truncated-001",
            "loader-empty-002",
            // The defect is the shape of the graph, not a field in it.
            "loader-program-expansion-036",
            "loader-call-cycle-014",
            "loader-unknown-call-target-015",
            "loader-stray-when-branch-022",
            "loader-unbounded-digits-to-integer-020",
            "loader-type-mismatch-012",
            // Measured, not assumed: see `leftPadFixtureCarriesASecondDefect`.
            "loader-left-pad-length-026",
            // The defect is a relationship between two declarations.
            "loader-orphan-definition-016",
            "loader-duplicate-prefix-017",
            "loader-undeclared-feature-006",
            "loader-predicate-constant-028",
            // The alphabet family: repairing means choosing an alphabet, which
            // is inventing a rule rather than undoing a mutation.
            "loader-alphabet-empty-031",
            "loader-alphabet-missing-033",
            "loader-alphabet-repeated-030",
            "loader-alphabet-too-many-032",
            "loader-alphabet-unread-034",
        ]

        #expect(repaired.isDisjoint(with: noRepairDefinable))
        #expect(repaired.union(noRepairDefinable) == all, "every loader fixture is accounted for")
    }
}
