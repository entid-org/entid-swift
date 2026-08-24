package import BusinessIDWire
import Testing

@testable import BusinessIDGenerator

/// Check 14 counts what a generator emits. No conformance case can see the
/// count: every reading of the rule agrees on the bundles an author writes, and
/// two engines have already answered differently on this one. Publishing the
/// profile is the only way two engines can compare it.
@Suite("Expansion")
struct ExpansionTests {
    @Test("The published bundle expands to the published profile")
    func publishedProfile() throws {
        let bundle = try RuleBundleLoader.load(try SpecCorpus.rulesBundle())
        #expect(bundle.expansion.programCount == 250)
        #expect(bundle.expansion.totalInstances == 3069)
        #expect(bundle.expansion.worstProgramID == 152)
        #expect(bundle.expansion.worstInstances == 118)
        #expect(bundle.expansion.worstNodeCount == 66)
        #expect(bundle.expansion.summary == "250 programs, 3069 instances, worst program 152 at 118")
    }

    /// The bundle carries fifty four captures and every one of them is reached
    /// from a root. Summing them all would report 3204 instances, which is the
    /// answer two engines gave.
    @Test("A capture reached by a root is not a second emission")
    func reachedCapturesAreNotCountedTwice() throws {
        let bundle = try RuleBundleLoader.load(try SpecCorpus.rulesBundle())
        let captures = bundle.programs.reduce(0) { $0 + $1.captures.count }
        #expect(captures == 54)

        let promoted = bundle.programs.reduce(0) { total, program in
            total + Expansion.emissionRoots(of: program).count - 1
        }
        #expect(promoted == 0, "no capture of the published bundle needs a root of its own")
    }

    @Test("Costs follow operands, so a node no root reaches costs nothing")
    func deadCodeCostsNothing() {
        // root reads node 1 only; node 0 is dead.
        let nodes = [
            IRNode(outputType: .string, inputs: [], operation: .string(.value)),
            IRNode(outputType: .string, inputs: [], operation: .string(.value)),
            IRNode(outputType: .boolean, inputs: [1], operation: .predicate(.isEmpty)),
        ]
        let program = IRProgram(id: 1, kind: .format, nodes: nodes, root: 2, captures: [], subject: nil)
        #expect(Expansion.instances(of: program) == 2)
    }

    @Test("A doubling chain is counted after inlining, not per node")
    func doublingChainExpands() {
        // Each level reads the previous one twice: 2^n instances from n nodes.
        var nodes: [IRNode] = [IRNode(outputType: .boolean, inputs: [], operation: .predicate(.all))]
        for index in 1...10 {
            nodes.append(
                IRNode(outputType: .boolean, inputs: [index - 1, index - 1], operation: .predicate(.all))
            )
        }
        let program = IRProgram(
            id: 1, kind: .format, nodes: nodes, root: nodes.count - 1, captures: [], subject: nil
        )
        // 1, 3, 7, 15 ... 2^(n+1) - 1
        #expect(Expansion.instances(of: program) == (1 << 11) - 1)
    }

    /// The corpus fixture for check 14, refused for the count and for nothing
    /// else.
    ///
    /// It has been wrong twice: it first rooted the doubling chain in the
    /// *format* program, then rooted a *checksum* program in a string. Both
    /// times an engine that never counted an instance refused it on the shape
    /// alone and passed the case for the wrong reason. Since `2026.08.25` the
    /// chain feeds a checksum node appended after it, so the shape is accepted
    /// and the count is what is left to object to.
    @Test("The expansion fixture is refused by the count, not by the program shape")
    func expansionFixtureIsRefusedForItsCount() throws {
        let payload = try SpecCorpus.loaderCases().first { $0.id == "loader-program-expansion-036" }
        let bundle = try Libbusinessid_Ir_V1_RuleBundle(
            serializedBytes: [UInt8](try #require(payload).rulesPayload)
        )
        let bytes: [UInt8] = try bundle.serializedBytes()

        var refusal: LoadError?
        do {
            _ = try RuleBundleLoader.load(bytes)
        } catch {
            refusal = error
        }
        let error = try #require(refusal)
        #expect(error.engineErrorName == "invalid_ruleset")
        // Forty doublings above a subject, then the checksum node the chain
        // feeds: 2^41 instances against a budget of 100000.
        #expect(error.reason.contains("expands to 2199023255552 operation instances"))
        #expect(error.reason.contains("beyond the budget of 100000"))
    }

    @Test("The arithmetic saturates rather than wrapping")
    func saturates() {
        #expect(Expansion.saturatingAdd(Int.max, 1) == Int.max)
        #expect(Expansion.saturatingAdd(Int.max, Int.max) == Int.max)
        #expect(Expansion.saturatingAdd(3, 4) == 7)
    }

    @Test("Captures are promoted from the highest index down")
    func capturesTakenFromTheTop() {
        // node 2 reads node 1; captures name both. Taken from the top, node 2
        // is promoted first and reaches node 1, so node 1 is not a second root.
        let nodes = [
            IRNode(outputType: .string, inputs: [], operation: .string(.value)),
            IRNode(outputType: .string, inputs: [0], operation: .string(.sliceFrom(start: 1))),
            IRNode(outputType: .string, inputs: [1], operation: .string(.sliceFrom(start: 1))),
            IRNode(outputType: .boolean, inputs: [], operation: .predicate(.all)),
            IRNode(
                outputType: .assertion, inputs: [3],
                operation: .assertion(.require(reason: .empty, messageKey: nil))),
            IRNode(outputType: .assertion, inputs: [4], operation: .assertion(.sequence)),
        ]
        let program = IRProgram(
            id: 1,
            kind: .format,
            nodes: nodes,
            root: 5,
            captures: [
                IRProgram.Capture(name: "inner", node: 1),
                IRProgram.Capture(name: "outer", node: 2),
            ],
            subject: nil
        )
        // Roots: the program root (3 instances) and capture "outer" (3
        // instances). "inner" is reached by "outer" and charges nothing more.
        #expect(Expansion.emissionRoots(of: program) == [5, 2])
        #expect(Expansion.instances(of: program) == 6)
    }
}
