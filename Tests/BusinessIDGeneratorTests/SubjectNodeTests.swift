package import BusinessIDWire
import Testing

@testable import BusinessIDGenerator

/// Check 15's clause on a subject node built from the subject it defines.
///
/// No program of the published bundle declares a `subject_node`, so the only
/// thing that exercises this clause is the corpus fixture — and the fixture
/// carries a second invalidity, which means passing its case does not prove the
/// clause is implemented. These cases isolate it.
@Suite("Circular subject node")
struct SubjectNodeTests {
    /// The corpus fixture, decoded so that one field at a time can be changed.
    static func fixture() throws -> Libbusinessid_Ir_V1_RuleBundle {
        let payload = try SpecCorpus.loaderCases()
            .first { $0.id == "loader-subject-node-circular-037" }
        return try Libbusinessid_Ir_V1_RuleBundle(
            serializedBytes: [UInt8](try #require(payload).rulesPayload)
        )
    }

    static func load(_ bundle: Libbusinessid_Ir_V1_RuleBundle) throws -> Result<Void, LoadError> {
        let bytes: [UInt8] = try bundle.serializedBytes()
        do {
            _ = try RuleBundleLoader.load(bytes)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    @Test("The corpus fixture is refused, and by the subject node clause of check 15")
    func fixtureIsRefusedForTheStatedReason() throws {
        // The expected error the runner compares is `invalid_ruleset`, which
        // several checks can produce. This asserts which one did.
        guard case .failure(let error) = try Self.load(try Self.fixture()) else {
            Issue.record("the fixture was accepted")
            return
        }
        #expect(error.engineErrorName == "invalid_ruleset")
        #expect(error.reason.contains("subject node reads subject()"))
        #expect(error.reason.contains("defines it in terms of itself"))
    }

    /// The fixture omits `CAPTURES_AND_CALLS_V1`, whose frozen content includes
    /// `Program.subject_node`, so check 25 refuses it too. An engine that never
    /// implemented the check 15 clause still passes the conformance case — for
    /// the wrong reason. Declaring the capability removes that second
    /// objection and leaves the circularity alone.
    @Test("With the capability declared, the circularity is the only objection left")
    func circularityAloneIsRefused() throws {
        var bundle = try Self.fixture()
        bundle.requiredFeatureIds = [1, 2, 3, 5, 10, 11, 20, 21, 30, 31, 40, 41]

        guard case .failure(let error) = try Self.load(bundle) else {
            Issue.record("a circular subject node was accepted")
            return
        }
        #expect(error.reason.contains("subject node reads subject()"))
    }

    @Test("Everything else in the fixture is a ruleset this generator stands behind")
    func theRestOfTheFixtureIsValid() throws {
        // Without this, the case above would prove nothing: a fixture refused
        // for some unrelated reason would satisfy it just as well.
        var bundle = try Self.fixture()
        bundle.requiredFeatureIds = [1, 2, 3, 5, 10, 11, 20, 21, 30, 31, 40, 41]
        bundle.programs[1].clearSubjectNode()

        if case .failure(let error) = try Self.load(bundle) {
            Issue.record(Comment(rawValue: "the fixture is invalid beyond its subject node: \(error)"))
        }
    }

    @Test("A subject node that does not read the subject it defines is accepted")
    func wellFoundedSubjectIsAccepted() throws {
        var bundle = try Self.fixture()
        bundle.requiredFeatureIds = [1, 2, 3, 5, 10, 11, 20, 21, 30, 31, 40, 41]

        // Replace the circular node with one built from `value()`, which is the
        // canonical value and not the subject being defined.
        var value = Libbusinessid_Ir_V1_StringOperation()
        value.kind = .value
        var node = Libbusinessid_Ir_V1_Node()
        node.outputType = .string
        node.stringOperation = value
        bundle.programs[1].nodes[6] = node

        if case .failure(let error) = try Self.load(bundle) {
            Issue.record(Comment(rawValue: "a well founded subject node was refused: \(error)"))
        }
    }

    @Test("The circularity is caught through a chain, not only through a direct read")
    func indirectCircularityIsRefused() throws {
        var bundle = try Self.fixture()
        bundle.requiredFeatureIds = [1, 2, 3, 5, 10, 11, 20, 21, 30, 31, 40, 41]

        // node 6 already reads node 0; add node 7 reading node 6 and point the
        // subject at 7. The read is now two levels down, which a check that
        // only inspected the subject node itself would miss.
        var slice = Libbusinessid_Ir_V1_StringOperation()
        slice.kind = .sliceFrom
        slice.start = 0
        var node = Libbusinessid_Ir_V1_Node()
        node.outputType = .string
        node.inputNodes = [6]
        node.stringOperation = slice
        bundle.programs[1].nodes.append(node)
        bundle.programs[1].subjectNode = 7

        guard case .failure(let error) = try Self.load(bundle) else {
            Issue.record("an indirectly circular subject node was accepted")
            return
        }
        #expect(error.reason.contains("subject node reads subject()"))
    }

    @Test("Declaring a subject node requires CAPTURES_AND_CALLS_V1")
    func subjectNodeRequiresItsCapability() throws {
        // The other half of what the fixture happens to carry: `subject_node`
        // is frozen content of capability 11, so using it without declaring it
        // is check 25's business.
        var bundle = try Self.fixture()
        bundle.programs[1].nodes[6] = {
            var value = Libbusinessid_Ir_V1_StringOperation()
            value.kind = .value
            var node = Libbusinessid_Ir_V1_Node()
            node.outputType = .string
            node.stringOperation = value
            return node
        }()

        guard case .failure(let error) = try Self.load(bundle) else {
            Issue.record("a subject node was accepted without its capability")
            return
        }
        #expect(error.reason.contains("CAPTURES_AND_CALLS_V1"))
    }
}
