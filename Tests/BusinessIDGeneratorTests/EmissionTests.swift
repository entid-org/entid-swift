import Testing

@testable import BusinessIDGenerator

/// The emitter, opcode by opcode.
///
/// The published bundle uses fifty two of the sixty three opcodes, so eleven
/// emitter branches are never reached by the conformance corpus. An opcode
/// added to the registry and forgotten in the emitter would compile, pass every
/// existing test, and fail the day a rule first used it — in a rules update
/// nobody would think to look at the emitter for.
@Suite("Emission")
struct EmissionTests {
    /// Nodes of every value type, so that the node under test always has an
    /// operand of the right shape to reference.
    ///
    /// Index 0 is a string, 1 an integer, 2 a boolean, 3 a canonicalization
    /// step, 4 an assertion and 5 a checksum outcome. The node under test is
    /// index 6.
    static let supply: [IRNode] = [
        IRNode(outputType: .string, inputs: [], operation: .string(.value)),
        IRNode(outputType: .integer, inputs: [0], operation: .integer(.digitsToInteger)),
        IRNode(outputType: .boolean, inputs: [0], operation: .predicate(.isEmpty)),
        IRNode(outputType: .canonicalizationStep, inputs: [], operation: .canonical(.trimWhitespace)),
        IRNode(
            outputType: .assertion,
            inputs: [2],
            operation: .assertion(.require(reason: .empty, messageKey: "k"))
        ),
        IRNode(outputType: .checksumOutcome, inputs: [0], operation: .checksum(.luhn(messageKey: nil))),
    ]

    static let stringOperand = 0
    static let integerOperand = 1
    static let booleanOperand = 2
    static let stepOperand = 3
    static let assertionOperand = 4
    static let outcomeOperand = 5

    /// One node per opcode, with operands of the types `ir.md` declares, and
    /// the fragment its emitted form must carry.
    static func sample(for opcode: Opcode) -> (node: IRNode, fragment: String) {
        func node(_ inputs: [Int], _ operation: Operation, _ type: ValueType) -> IRNode {
            IRNode(outputType: type, inputs: inputs, operation: operation)
        }
        let text = [stringOperand]
        let integer = [integerOperand]
        let boolean = [booleanOperand]

        switch opcode {
        case .stringConstant:
            return (node([], .string(.constant("FR")), .string), "ScalarView(GeneratedLiterals.")
        case .stringValue:
            return (node([], .string(.value), .string), "ScalarView(c.value)")
        case .stringSubject:
            return (node([], .string(.subject), .string), "subjectView()")
        case .stringCountryCode:
            return (node([], .string(.countryCode), .string), "c.country.map(ScalarView.init)")
        case .stringSlice:
            return (node(text, .string(.slice(start: 1, end: 4)), .string), ".slice(start: 1, end: 4)")
        case .stringSliceFrom:
            return (node(text, .string(.sliceFrom(start: 2)), .string), ".slice(from: 2)")
        case .stringSliceTo:
            return (node(text, .string(.sliceTo(end: 3)), .string), ".slice(to: 3)")
        case .stringBeforeFirst:
            return (node(text, .string(.beforeFirst(".")), .string), ".before(first: GeneratedLiterals.")
        case .stringAfterFirst:
            return (node(text, .string(.afterFirst(".")), .string), ".after(first: GeneratedLiterals.")
        case .stringStripPrefix:
            return (node(text, .string(.stripPrefix("FR")), .string), ".strippingPrefix(GeneratedLiterals.")
        case .stringConcat:
            return (node([0, 0], .string(.concat), .string), "ScalarView.concatenating([")

        case .integerDigitsToInteger:
            return (node(text, .integer(.digitsToInteger), .integer), "IntegerOps.digitsToInteger(")
        case .integerModDigits:
            return (node(text, .integer(.modDigits(modulus: 97)), .integer), "modulus: 97")
        case .integerWeightedSum:
            return (
                node(
                    text,
                    .integer(
                        .weightedSum(weights: [1, 2], alignment: .cycle, mapping: .digitValue, alphabet: nil)
                    ),
                    .integer
                ),
                "alignment: .cycle, mapping: .digitValue"
            )
        case .integerModulo:
            return (node(integer, .integer(.modulo(modulus: 11)), .integer), "IntegerOps.modulo(")
        case .integerComplement:
            return (node(integer, .integer(.complement(modulus: 11)), .integer), "IntegerOps.complement(")
        case .integerRemainderMap:
            return (
                node(integer, .integer(.remainderMap(values: [1, 2, 3])), .integer),
                "IntegerOps.remainderMap("
            )

        case .predicateIsEmpty:
            return (node(text, .predicate(.isEmpty), .boolean), ".isEmptyView")
        case .predicateIsAbsent:
            return (node(text, .predicate(.isAbsent), .boolean), ".isAbsent")
        case .predicateEquals:
            return (node([0, 0], .predicate(.equals), .boolean), ".matches(")
        case .predicateLengthEq:
            return (node(text, .predicate(.lengthEq(9)), .boolean), "Predicates.lengthEq(")
        case .predicateLengthIn:
            return (node(text, .predicate(.lengthIn([8, 9])), .boolean), "Predicates.lengthIn(")
        case .predicateLengthBetween:
            return (
                node(text, .predicate(.lengthBetween(min: 2, max: 7)), .boolean),
                "Predicates.lengthBetween(n0(), 2, 7)"
            )
        case .predicateAsciiDigits:
            return (node(text, .predicate(.asciiDigits), .boolean), "ASCIIClass.isDigit")
        case .predicateAsciiUpperLetters:
            return (node(text, .predicate(.asciiUpperLetters), .boolean), "ASCIIClass.isUpperLetter")
        case .predicateAsciiAlphanumeric:
            return (node(text, .predicate(.asciiAlphanumeric), .boolean), "ASCIIClass.isAlphanumeric")
        case .predicateAsciiCharset:
            return (node(text, .predicate(.asciiCharset(["A", "B"])), .boolean), "Predicates.asciiCharset(")
        case .predicateStartsWith:
            return (node(text, .predicate(.startsWith("FR")), .boolean), ".hasPrefix(GeneratedLiterals.")
        case .predicateEndsWith:
            return (node(text, .predicate(.endsWith("Z")), .boolean), ".hasSuffix(GeneratedLiterals.")
        case .predicatePrefixIn:
            return (node(text, .predicate(.prefixIn(["EL", "GR"])), .boolean), "Predicates.prefixIn(")
        case .predicateCharAtIn:
            return (
                node(text, .predicate(.charAtIn(index: 1, chars: ["0"])), .boolean), "Predicates.charAtIn("
            )
        case .predicateContains:
            return (node(text, .predicate(.contains(".")), .boolean), ".contains(GeneratedLiterals.")
        case .predicateAll:
            return (node([2, 2], .predicate(.all), .boolean), "n2() && n2()")
        case .predicateAny:
            return (node([2, 2], .predicate(.any), .boolean), "n2() || n2()")
        case .predicateNot:
            return (node(boolean, .predicate(.not), .boolean), "!n2()")
        case .predicateProfileIs:
            return (
                node([], .predicate(.profileIs("strict_current")), .boolean),
                "c.profile == .strictCurrent"
            )
        case .predicateIntegerIs:
            return (node(integer, .predicate(.integerIs(5)), .boolean), "n1() == Int64(5)")

        case .canonicalSequence:
            return (node([3], .canonical(.sequence), .canonicalizationStep), "n3(&v)")
        case .canonicalTrimWhitespace:
            return (
                node([], .canonical(.trimWhitespace), .canonicalizationStep),
                "CanonicalizationSteps.trimWhitespace(&v)"
            )
        case .canonicalRemoveWhitespace:
            return (
                node([], .canonical(.removeWhitespace), .canonicalizationStep),
                "CanonicalizationSteps.removeWhitespace(&v)"
            )
        case .canonicalUppercaseASCII:
            return (
                node([], .canonical(.uppercaseASCII), .canonicalizationStep),
                "CanonicalizationSteps.uppercaseASCII(&v)"
            )
        case .canonicalRemoveChars:
            return (
                node([], .canonical(.removeChars([".", "-"])), .canonicalizationStep),
                "CanonicalizationSteps.removeChars(&v"
            )
        case .canonicalReplacePrefix:
            return (
                node([], .canonical(.replacePrefix(text: "GR", replacement: "EL")), .canonicalizationStep),
                "CanonicalizationSteps.replacePrefix(&v"
            )
        case .canonicalPrepend:
            return (
                node([], .canonical(.prepend("FR")), .canonicalizationStep),
                "CanonicalizationSteps.prepend(&v"
            )
        case .canonicalAppend:
            return (
                node([], .canonical(.append("Z")), .canonicalizationStep),
                "CanonicalizationSteps.append(&v"
            )
        case .canonicalInsert:
            return (
                node([], .canonical(.insert(index: 2, text: "-")), .canonicalizationStep),
                "CanonicalizationSteps.insert(&v, at: 2"
            )
        case .canonicalLeftPad:
            return (
                node([], .canonical(.leftPad(length: 9, pad: "0")), .canonicalizationStep),
                "CanonicalizationSteps.leftPad(&v, to: 9, with: \"0\")"
            )
        case .canonicalPrependCountryIfMissing:
            return (
                node([], .canonical(.prependCountryIfMissing), .canonicalizationStep),
                "acceptedPrefixes: c.acceptedPrefixes"
            )
        case .canonicalWhen:
            return (node([2, 3], .canonical(.when), .canonicalizationStep), "if n2(v) {")

        case .assertionSequence:
            return (node([4, 4], .assertion(.sequence), .assertion), "if case .fail = a0 { return a0 }")
        case .assertionRequire:
            return (
                node(boolean, .assertion(.require(reason: .invalidLength, messageKey: "a.b")), .assertion),
                ".fail(.invalidLength, \"a.b\")"
            )

        case .checksumLuhn:
            return (node(text, .checksum(.luhn(messageKey: "k")), .checksumOutcome), "ChecksumOps.luhn(")
        case .checksumIso7064Mod9710:
            return (
                node(text, .checksum(.iso7064Mod97Dash10(messageKey: nil)), .checksumOutcome),
                "ChecksumOps.iso7064Mod97Dash10("
            )
        case .checksumCompareDigit:
            return (
                node([1, 0], .checksum(.compareDigit(index: 8, messageKey: nil)), .checksumOutcome),
                "ChecksumOps.compareDigit(n1(), n0(), index: 8"
            )
        case .checksumCompareSlice:
            return (
                node([1, 0], .checksum(.compareSlice(start: 2, end: 4, messageKey: nil)), .checksumOutcome),
                "ChecksumOps.compareSlice(n1(), n0(), start: 2, end: 4"
            )
        case .checksumChoose:
            return (node([5, 5], .checksum(.choose), .checksumOutcome), "ChecksumOps.choose([")
        case .checksumWhen:
            return (node([2, 5], .checksum(.when), .checksumOutcome), "n2() ? n5() : .notApplicable")
        case .checksumAllChecks:
            return (node([5, 5], .checksum(.allChecks), .checksumOutcome), "ChecksumOps.allChecks([")
        case .checksumAnyCheck:
            return (node([5, 5], .checksum(.anyCheck), .checksumOutcome), "ChecksumOps.anyCheck([")
        case .checksumUnsupported:
            let unsupported = ChecksumOp.unsupported(reason: .checksumNotPublished, messageKey: nil)
            return (
                node([], .checksum(unsupported), .checksumOutcome),
                ".unsupported(.checksumNotPublished, nil)"
            )
        case .checksumCompareConstant:
            return (
                node(integer, .checksum(.compareConstant(constant: 0, messageKey: "k")), .checksumOutcome),
                "ChecksumOps.compareConstant(n1(), 0"
            )

        case .callFormat:
            return (
                node(text, .call(.format(programID: 42)), .assertion), "GeneratedPrograms.format42(c, n0())"
            )
        case .callChecksum:
            return (
                node(text, .call(.checksum(programID: 42)), .checksumOutcome),
                "GeneratedPrograms.checksum42(c, n0())"
            )
        }
    }

    /// A canonicalization program threads the current value through its nodes;
    /// the other two do not, and the emitted signatures differ accordingly.
    static func programKind(for opcode: Opcode) -> ProgramKind {
        switch opcode.outputType {
        case .canonicalizationStep: .canonicalization
        case .assertion: .format
        default: .checksum
        }
    }

    @Test("Every opcode of the registry has an emitter branch", arguments: Opcode.allCases)
    func everyOpcodeEmits(opcode: Opcode) {
        let sample = Self.sample(for: opcode)
        #expect(sample.node.operation.opcode == opcode, "the sample must be of the opcode under test")

        let program = IRProgram(
            id: 7,
            kind: Self.programKind(for: opcode),
            nodes: Self.supply + [sample.node],
            root: Self.supply.count,
            captures: [],
            subject: nil
        )
        var out = SwiftSource()
        var literals = LiteralTable()
        ProgramEmitter(program: program).render(into: &out, literals: &literals)

        #expect(
            out.text.contains(sample.fragment),
            Comment(rawValue: "\(opcode.rawValue) emitted:\n\(out.text)")
        )
    }

    @Test("Only the nodes an emission root reaches are emitted")
    func deadCodeIsNotEmitted() {
        let nodes = [
            IRNode(outputType: .string, inputs: [], operation: .string(.value)),
            // Nothing reads this one.
            IRNode(outputType: .string, inputs: [], operation: .string(.constant("dead"))),
            IRNode(outputType: .boolean, inputs: [0], operation: .predicate(.isEmpty)),
            IRNode(
                outputType: .assertion,
                inputs: [2],
                operation: .assertion(.require(reason: .empty, messageKey: nil))
            ),
            IRNode(outputType: .assertion, inputs: [3], operation: .assertion(.sequence)),
        ]
        let program = IRProgram(
            id: 1, kind: .format, nodes: nodes, root: 4, captures: [], subject: nil
        )
        var out = SwiftSource()
        var literals = LiteralTable()
        ProgramEmitter(program: program).render(into: &out, literals: &literals)

        #expect(!out.text.contains("func n1()"))
        #expect(out.text.contains("func n0()"))
        #expect(literals.scalarLiterals.isEmpty, "a dead constant reaches no literal table")
    }

    @Test("A capture is reachable even when the program root does not read it")
    func capturesAreEmitted() {
        let nodes = [
            IRNode(outputType: .string, inputs: [], operation: .string(.value)),
            IRNode(outputType: .string, inputs: [0], operation: .string(.sliceFrom(start: 2))),
            IRNode(outputType: .boolean, inputs: [0], operation: .predicate(.isEmpty)),
            IRNode(
                outputType: .assertion,
                inputs: [2],
                operation: .assertion(.require(reason: .empty, messageKey: nil))
            ),
            IRNode(outputType: .assertion, inputs: [3], operation: .assertion(.sequence)),
        ]
        let program = IRProgram(
            id: 1,
            kind: .format,
            nodes: nodes,
            root: 4,
            captures: [IRProgram.Capture(name: "tail", node: 1)],
            subject: nil
        )
        var out = SwiftSource()
        var literals = LiteralTable()
        ProgramEmitter(program: program).render(into: &out, literals: &literals)
        #expect(out.text.contains("func n1()"))
    }

    @Test("A declared subject node becomes the fallback of subject()")
    func subjectNodeIsTheFallback() {
        let nodes = [
            IRNode(outputType: .string, inputs: [], operation: .string(.value)),
            IRNode(outputType: .string, inputs: [0], operation: .string(.sliceFrom(start: 2))),
            IRNode(outputType: .string, inputs: [], operation: .string(.subject)),
            IRNode(outputType: .boolean, inputs: [2], operation: .predicate(.isEmpty)),
            IRNode(
                outputType: .assertion,
                inputs: [3],
                operation: .assertion(.require(reason: .empty, messageKey: nil))
            ),
            IRNode(outputType: .assertion, inputs: [4], operation: .assertion(.sequence)),
        ]
        let program = IRProgram(
            id: 1, kind: .format, nodes: nodes, root: 5, captures: [], subject: 1
        )
        var out = SwiftSource()
        var literals = LiteralTable()
        ProgramEmitter(program: program).render(into: &out, literals: &literals)
        #expect(out.text.contains("func subjectView() -> ScalarView { suppliedSubject ?? n1() }"))
    }

    @Test("Literals are named once and shared")
    func literalsAreShared() {
        var literals = LiteralTable()
        let first = literals.name(text: "FR")
        let second = literals.name(text: "FR")
        let other = literals.name(text: "BE")
        #expect(first == second)
        #expect(first != other)
        #expect(literals.scalarLiterals.count == 2)

        #expect(literals.name(integers: [1, 2]) == literals.name(integers: [1, 2]))
        #expect(literals.name(lengths: [8, 9]) == literals.name(lengths: [8, 9]))
        #expect(literals.name(texts: ["EL"]) == literals.name(texts: ["EL"]))
    }

    @Test("A literal is emitted as the text it is, escaped to stay ASCII")
    func literalEscaping() {
        #expect(SwiftSource.quote("FR") == "\"FR\"")
        #expect(SwiftSource.quote("a\"b") == "\"a\\\"b\"")
        #expect(SwiftSource.quote("a\\b") == "\"a\\\\b\"")
        #expect(SwiftSource.quote("\u{00A0}") == "\"\\u{A0}\"")
        #expect(SwiftSource.quote("\n") == "\"\\n\"")
    }
}
