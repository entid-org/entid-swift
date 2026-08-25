package import EntIDWire
import Testing

@testable import EntIDGenerator

/// Check 15's clause on a subject node built from the subject it defines.
///
/// The corpus fixture now isolates the clause, so the base case is covered by
/// `FixtureRepairTests`: repairing the circularity makes the bundle load. What
/// remains here is what the fixture does not reach.
@Suite("Circular subject node")
struct SubjectNodeTests {
    static func fixture() throws -> Libbusinessid_Ir_V1_RuleBundle {
        let payload = try SpecCorpus.loaderCases()
            .first { $0.id == "loader-subject-node-circular-037" }
        return try Libbusinessid_Ir_V1_RuleBundle(
            serializedBytes: [UInt8](try #require(payload).rulesPayload)
        )
    }

    static func load(_ bundle: Libbusinessid_Ir_V1_RuleBundle) throws -> LoadError? {
        let bytes: [UInt8] = try bundle.serializedBytes()
        do {
            _ = try RuleBundleLoader.load(bytes)
            return nil
        } catch {
            return error
        }
    }

    @Test("The fixture is refused by the subject node clause, not by something else")
    func refusedForTheStatedReason() throws {
        // The error the runner compares is `invalid_ruleset`, which every
        // structural check produces. This asserts which one did.
        let error = try #require(try Self.load(try Self.fixture()))
        #expect(error.engineErrorName == "invalid_ruleset")
        #expect(error.reason.contains("subject node reads subject()"))
        #expect(error.reason.contains("defines it in terms of itself"))
    }

    @Test("The circularity is caught through a chain, not only through a direct read")
    func indirectCircularityIsRefused() throws {
        // The fixture reads `subject()` one level below the subject node. A
        // check that inspected only the subject node itself would pass it and
        // still recurse forever on this.
        var bundle = try Self.fixture()
        var slice = Libbusinessid_Ir_V1_StringOperation()
        slice.kind = .sliceFrom
        slice.start = 0
        var node = Libbusinessid_Ir_V1_Node()
        node.outputType = .string
        node.inputNodes = [6]
        node.stringOperation = slice
        bundle.programs[1].nodes.append(node)
        bundle.programs[1].subjectNode = 7

        let error = try #require(try Self.load(bundle))
        #expect(error.reason.contains("subject node reads subject()"))
    }

    /// `features.md` section 11 lists `Program.subject_node` among the frozen
    /// content of `CAPTURES_AND_CALLS_V1`, so a bundle declaring one uses that
    /// capability and must declare it.
    ///
    /// This is the defect the reference loader carried: it derived the
    /// capability from captures alone and ignored the field, so it accepted
    /// what this engine refused. The case exists to keep this engine from
    /// drifting the same way.
    @Test("Declaring a subject node requires CAPTURES_AND_CALLS_V1")
    func subjectNodeRequiresItsCapability() throws {
        var bundle = try Self.fixture()

        // Repair the circularity first, so the capability is the only thing
        // left to object to.
        var value = Libbusinessid_Ir_V1_StringOperation()
        value.kind = .value
        var node = Libbusinessid_Ir_V1_Node()
        node.outputType = .string
        node.stringOperation = value
        bundle.programs[1].nodes[Int(bundle.programs[1].subjectNode)] = node
        #expect(try Self.load(bundle) == nil, "the repaired fixture must load")

        // Now take the capability away and nothing else.
        bundle.requiredFeatureIds.removeAll { $0 == Capability.capturesAndCallsV1 }
        let error = try #require(try Self.load(bundle))
        #expect(error.reason.contains("CAPTURES_AND_CALLS_V1"))
        #expect(error.reason.contains("subject_node"))
    }

    @Test("A capture also requires the capability, and neither implies the other")
    func capturesAndSubjectAreIndependent() throws {
        // Deriving the capability from captures alone is what let a subject
        // node through. Deriving it from the subject node alone would let a
        // capture through, so both are asserted.
        var bundle = try Self.fixture()
        bundle.programs[1].clearSubjectNode()
        bundle.programs[1].nodes.removeLast()
        bundle.requiredFeatureIds.removeAll { $0 == Capability.capturesAndCallsV1 }
        #expect(try Self.load(bundle) == nil, "without either construct the capability is not used")

        var capture = Libbusinessid_Ir_V1_Capture()
        capture.name = "whole"
        capture.node = 0
        bundle.programs[1].captures = [capture]
        let error = try #require(try Self.load(bundle))
        #expect(error.reason.contains("CAPTURES_AND_CALLS_V1"))
    }
}
