package import EntIDWire

import struct Foundation.Data

/// Builds a minimal bundle that passes every load check, so that a test can
/// break exactly one thing and watch the right check refuse it.
///
/// Mutating the published bundle would work too, but it would not say which
/// property a test is about: a builder that starts from the smallest accepted
/// ruleset makes the one changed line the subject of the test.
enum BundleBuilder {
    typealias Bundle = Entid_Ir_V1_RuleBundle
    typealias Program = Entid_Ir_V1_Program
    typealias Node = Entid_Ir_V1_Node

    // MARK: Nodes

    static func string(_ kind: Entid_Ir_V1_StringOpKind, inputs: [UInt32] = []) -> Node {
        var operation = Entid_Ir_V1_StringOperation()
        operation.kind = kind
        var node = Node()
        node.outputType = .string
        node.inputNodes = inputs
        node.stringOperation = operation
        return node
    }

    static func slice(_ input: UInt32, start: UInt32, end: UInt32) -> Node {
        var operation = Entid_Ir_V1_StringOperation()
        operation.kind = .slice
        operation.start = start
        operation.end = end
        var node = Node()
        node.outputType = .string
        node.inputNodes = [input]
        node.stringOperation = operation
        return node
    }

    static func predicate(
        _ kind: Entid_Ir_V1_PredicateOpKind,
        inputs: [UInt32] = [],
        configure: (inout Entid_Ir_V1_PredicateOperation) -> Void = { _ in }
    ) -> Node {
        var operation = Entid_Ir_V1_PredicateOperation()
        operation.kind = kind
        configure(&operation)
        var node = Node()
        node.outputType = .boolean
        node.inputNodes = inputs
        node.predicateOperation = operation
        return node
    }

    static func require(
        _ input: UInt32,
        reason: Entid_Ir_V1_ReasonCode = .empty,
        messageKey: String? = nil
    ) -> Node {
        var operation = Entid_Ir_V1_AssertionOperation()
        operation.kind = .require
        operation.reasonCode = reason
        if let messageKey { operation.messageKey = messageKey }
        var node = Node()
        node.outputType = .assertion
        node.inputNodes = [input]
        node.assertionOperation = operation
        return node
    }

    static func assertionSequence(_ inputs: [UInt32]) -> Node {
        var operation = Entid_Ir_V1_AssertionOperation()
        operation.kind = .sequence
        var node = Node()
        node.outputType = .assertion
        node.inputNodes = inputs
        node.assertionOperation = operation
        return node
    }

    static func canonical(
        _ kind: Entid_Ir_V1_CanonicalizationOpKind,
        inputs: [UInt32] = [],
        configure: (inout Entid_Ir_V1_CanonicalizationOperation) -> Void = { _ in }
    ) -> Node {
        var operation = Entid_Ir_V1_CanonicalizationOperation()
        operation.kind = kind
        configure(&operation)
        var node = Node()
        node.outputType = .canonicalizationStep
        node.inputNodes = inputs
        node.canonicalizationOperation = operation
        return node
    }

    static func checksum(_ kind: Entid_Ir_V1_ChecksumOpKind, inputs: [UInt32] = []) -> Node {
        var operation = Entid_Ir_V1_ChecksumOperation()
        operation.kind = kind
        var node = Node()
        node.outputType = .checksumOutcome
        node.inputNodes = inputs
        node.checksumOperation = operation
        return node
    }

    static func call(
        _ kind: Entid_Ir_V1_CallOpKind,
        program: UInt32,
        input: UInt32
    ) -> Node {
        var operation = Entid_Ir_V1_CallOperation()
        operation.kind = kind
        operation.programID = program
        var node = Node()
        node.outputType = kind == .format ? .assertion : .checksumOutcome
        node.inputNodes = [input]
        node.callOperation = operation
        return node
    }

    static func program(
        id: UInt32,
        kind: Entid_Ir_V1_ProgramKind,
        nodes: [Node],
        root: UInt32
    ) -> Program {
        var program = Program()
        program.id = id
        program.kind = kind
        program.nodes = nodes
        program.rootNode = root
        return program
    }

    // MARK: Bundle

    /// Programs 1 (pre-canonicalization), 2 (canonicalization) and 3 (format);
    /// one GLOBAL definition of kind `test`; one dispatcher routing to it.
    static func minimal() -> Bundle {
        var bundle = Entid_Ir_V1_RuleBundle()
        bundle.formatVersion = 1
        bundle.rulesVersion = "2026.08.17"
        bundle.requiredFeatureIds = [1, 2, 3, 5, 20, 21, 30, 40]
        bundle.sourceDigest = Data([UInt8](repeating: 0xAB, count: 32))

        bundle.programs = [
            program(
                id: 1,
                kind: .canonicalization,
                nodes: [canonical(.trimWhitespace), canonical(.sequence, inputs: [0])],
                root: 1
            ),
            program(
                id: 2,
                kind: .canonicalization,
                nodes: [canonical(.uppercaseAscii), canonical(.sequence, inputs: [0])],
                root: 1
            ),
            program(
                id: 3,
                kind: .format,
                nodes: [
                    string(.subject),
                    predicate(.isEmpty, inputs: [0]),
                    predicate(.not, inputs: [1]),
                    require(2, reason: .empty, messageKey: "test.empty"),
                    assertionSequence([3]),
                ],
                root: 4
            ),
        ]

        var source = Entid_Ir_V1_Source()
        source.id = "test-authority"
        source.url = "https://example.invalid/spec"
        source.authority = "Test authority"
        source.title = "Test format"
        source.accessedAt = "2026-08-17"

        var definition = Entid_Ir_V1_IdentifierDefinition()
        definition.id = 1
        definition.kind = "test"
        definition.canonicalizationProgram = 2
        definition.formatProgram = 3
        definition.defaultProfile = "compatible"
        definition.sources = [source]
        definition.absentChecksumReason = .checksumNotPublished
        bundle.identifiers = [definition]

        var target = Entid_Ir_V1_DispatchTarget()
        target.identifierDefinitionID = 1

        var dispatcher = Entid_Ir_V1_IdentifierDispatcher()
        dispatcher.kind = "test"
        dispatcher.preCanonicalizationProgram = 1
        dispatcher.targets = [target]
        bundle.dispatchers = [dispatcher]

        return bundle
    }

    static func bytes(_ bundle: Bundle) throws -> [UInt8] {
        try bundle.serializedBytes()
    }
}
