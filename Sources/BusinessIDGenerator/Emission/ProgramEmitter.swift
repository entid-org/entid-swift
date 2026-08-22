/// Emits one IR program as a Swift function.
///
/// Each node becomes a local function, and an operand reference becomes a call.
/// That is sharing rather than inlining, which `ir.md` section 2 permits
/// provided the short circuit of `ALL`, `ANY` and of the assertion sequence is
/// preserved — and a call inside `&&` or before an early `return` preserves it
/// exactly. It also keeps the emitted code linear in the node count where
/// inlining would be exponential.
///
/// No node is memoized: a local function runs again at every reference, which
/// is what `value()` inside a canonicalization program depends on.
///
/// Only the nodes an emission root reaches are emitted. A node no root reaches
/// is dead code and costs nothing, here and in the check 14 count.
struct ProgramEmitter {
    let program: IRProgram

    /// Whether the enclosing program threads the current value through its
    /// nodes, which only a canonicalization program does.
    private var isCanonicalization: Bool { program.kind == .canonicalization }

    func render(into out: inout SwiftSource, literals: inout LiteralTable) {
        let reachable = reachableNodes()

        switch program.kind {
        case .canonicalization:
            out.line(
                "static func canon\(program.id)("
                    + "_ v: inout [Unicode.Scalar], _ c: CanonicalizationContext) {"
            )
        case .format:
            out.line(
                "static func format\(program.id)("
                    + "_ c: RuleContext, _ suppliedSubject: ScalarView?) -> AssertionOutcome {"
            )
        case .checksum:
            out.line(
                "static func checksum\(program.id)("
                    + "_ c: RuleContext, _ suppliedSubject: ScalarView?) -> ChecksumOutcome {"
            )
        }
        out.push()

        if !isCanonicalization {
            // `subject()` is the caller supplied view for a called program,
            // otherwise the program's own subject node, otherwise the canonical
            // value.
            let fallback = program.subject.map { "n\($0)()" } ?? "ScalarView(c.value)"
            out.line("func subjectView() -> ScalarView { suppliedSubject ?? \(fallback) }")
        }

        for index in program.nodes.indices where reachable.contains(index) {
            renderNode(at: index, into: &out, literals: &literals)
        }

        switch program.kind {
        case .canonicalization: out.line("n\(program.root)(&v)")
        default: out.line("return n\(program.root)()")
        }

        out.pop()
        out.line("}")
    }

    /// The nodes reachable from the emission roots: the program root, the
    /// subject node, and every capture.
    private func reachableNodes() -> Set<Int> {
        var reached: Set<Int> = []
        func mark(_ index: Int) {
            guard reached.insert(index).inserted else { return }
            for operand in program.nodes[index].inputs { mark(operand) }
        }
        mark(program.root)
        if let subject = program.subject { mark(subject) }
        for capture in program.captures { mark(capture.node) }
        return reached
    }

    // MARK: - Nodes

    private func renderNode(at index: Int, into out: inout SwiftSource, literals: inout LiteralTable) {
        let node = program.nodes[index]
        let valueParameter = isCanonicalization ? "_ v: [Unicode.Scalar]" : ""

        switch node.operation {
        case .string(let operation):
            out.line("func n\(index)(\(valueParameter)) -> ScalarView {")
            out.push()
            out.line(stringExpression(operation, node: node, literals: &literals))
            out.pop()
            out.line("}")

        case .integer(let operation):
            out.line("func n\(index)() -> IntegerValue {")
            out.push()
            out.line(integerExpression(operation, node: node, literals: &literals))
            out.pop()
            out.line("}")

        case .predicate(let operation):
            out.line("func n\(index)(\(valueParameter)) -> Bool {")
            out.push()
            out.line(predicateExpression(operation, node: node, literals: &literals))
            out.pop()
            out.line("}")

        case .canonical(let operation):
            out.line("func n\(index)(_ v: inout [Unicode.Scalar]) {")
            out.push()
            out.lines(canonicalStatements(operation, node: node, literals: &literals))
            out.pop()
            out.line("}")

        case .assertion(let operation):
            out.line("func n\(index)() -> AssertionOutcome {")
            out.push()
            out.lines(assertionStatements(operation, node: node, literals: &literals))
            out.pop()
            out.line("}")

        case .checksum(let operation):
            out.line("func n\(index)() -> ChecksumOutcome {")
            out.push()
            out.lines(checksumStatements(operation, node: node, literals: &literals))
            out.pop()
            out.line("}")

        case .call(let operation):
            switch operation {
            case .format(let target):
                out.line("func n\(index)() -> AssertionOutcome {")
                out.push()
                out.line("GeneratedPrograms.format\(target)(c, \(reference(node.inputs[0])))")
            case .checksum(let target):
                out.line("func n\(index)() -> ChecksumOutcome {")
                out.push()
                out.line("GeneratedPrograms.checksum\(target)(c, \(reference(node.inputs[0])))")
            }
            out.pop()
            out.line("}")
        }
    }

    /// A call to the local function of an operand.
    private func reference(_ index: Int) -> String {
        isCanonicalization ? "n\(index)(v)" : "n\(index)()"
    }

    // MARK: - Expressions

    private func stringExpression(
        _ operation: StringOp,
        node: IRNode,
        literals: inout LiteralTable
    ) -> String {
        switch operation {
        case .constant(let text):
            "ScalarView(GeneratedLiterals.\(literals.name(text: text)))"
        case .value:
            isCanonicalization ? "ScalarView(v)" : "ScalarView(c.value)"
        case .subject:
            "subjectView()"
        case .countryCode:
            "c.country.map(ScalarView.init) ?? ScalarView.absent"
        case .slice(let start, let end):
            "\(reference(node.inputs[0])).slice(start: \(start), end: \(end))"
        case .sliceFrom(let start):
            "\(reference(node.inputs[0])).slice(from: \(start))"
        case .sliceTo(let end):
            "\(reference(node.inputs[0])).slice(to: \(end))"
        case .beforeFirst(let text):
            "\(reference(node.inputs[0])).before(first: GeneratedLiterals.\(literals.name(text: text)))"
        case .afterFirst(let text):
            "\(reference(node.inputs[0])).after(first: GeneratedLiterals.\(literals.name(text: text)))"
        case .stripPrefix(let text):
            "\(reference(node.inputs[0]))"
                + ".strippingPrefix(GeneratedLiterals.\(literals.name(text: text)))"
        case .concat:
            "ScalarView.concatenating([\(node.inputs.map(reference).joined(separator: ", "))])"
        }
    }

    private func integerExpression(
        _ operation: IntegerOp,
        node: IRNode,
        literals: inout LiteralTable
    ) -> String {
        let operand = reference(node.inputs[0])
        switch operation {
        case .digitsToInteger:
            return "IntegerOps.digitsToInteger(\(operand))"
        case .modDigits(let modulus):
            return "IntegerOps.modDigits(\(operand), modulus: \(modulus))"
        case .modulo(let modulus):
            return "IntegerOps.modulo(\(operand), modulus: \(modulus))"
        case .complement(let modulus):
            return "IntegerOps.complement(\(operand), modulus: \(modulus))"
        case .remainderMap(let values):
            let table = literals.name(integers: values)
            return "IntegerOps.remainderMap(\(operand), values: GeneratedLiterals.\(table))"
        case .weightedSum(let weights, let alignment, let mapping, let alphabet):
            let alignmentCase =
                switch alignment {
                case .left: ".left"
                case .right: ".right"
                case .cycle: ".cycle"
                }
            let mappingCase: String =
                switch mapping {
                case .digitValue: ".digitValue"
                case .alnumBase36: ".alnumBase36"
                case .customAlphabet:
                    ".customAlphabet(GeneratedLiterals.\(literals.name(scalars: alphabet ?? [])))"
                }
            return "IntegerOps.weightedSum(\(operand), weights: GeneratedLiterals."
                + "\(literals.name(integers: weights)), alignment: \(alignmentCase), "
                + "mapping: \(mappingCase))"
        }
    }

    private func predicateExpression(
        _ operation: PredicateOp,
        node: IRNode,
        literals: inout LiteralTable
    ) -> String {
        func operand(_ position: Int = 0) -> String { reference(node.inputs[position]) }
        switch operation {
        case .isEmpty: return "\(operand()).isEmptyView"
        case .isAbsent: return "\(operand()).isAbsent"
        case .equals: return "\(operand(0)).matches(\(operand(1)))"
        case .lengthEq(let length): return "Predicates.lengthEq(\(operand()), \(length))"
        case .lengthIn(let lengths):
            return "Predicates.lengthIn(\(operand()), GeneratedLiterals.\(literals.name(lengths: lengths)))"
        case .lengthBetween(let minimum, let maximum):
            return "Predicates.lengthBetween(\(operand()), \(minimum), \(maximum))"
        case .asciiDigits: return "\(operand()).allSatisfyNonEmpty(ASCIIClass.isDigit)"
        case .asciiUpperLetters: return "\(operand()).allSatisfyNonEmpty(ASCIIClass.isUpperLetter)"
        case .asciiAlphanumeric: return "\(operand()).allSatisfyNonEmpty(ASCIIClass.isAlphanumeric)"
        case .asciiCharset(let chars):
            return "Predicates.asciiCharset(\(operand()), GeneratedLiterals.\(literals.name(scalars: chars)))"
        case .startsWith(let text):
            return "\(operand()).hasPrefix(GeneratedLiterals.\(literals.name(text: text)))"
        case .endsWith(let text):
            return "\(operand()).hasSuffix(GeneratedLiterals.\(literals.name(text: text)))"
        case .prefixIn(let values):
            return "Predicates.prefixIn(\(operand()), GeneratedLiterals.\(literals.name(texts: values)))"
        case .charAtIn(let index, let chars):
            return "Predicates.charAtIn(\(operand()), \(index), "
                + "GeneratedLiterals.\(literals.name(scalars: chars)))"
        case .contains(let text):
            return "\(operand()).contains(GeneratedLiterals.\(literals.name(text: text)))"
        case .all:
            // Operands are evaluated in order and evaluation stops at the first
            // false one, which `&&` is.
            return node.inputs.map(reference).joined(separator: " && ")
        case .any:
            return node.inputs.map(reference).joined(separator: " || ")
        case .not:
            return "!\(operand())"
        case .profileIs(let name):
            return "c.profile == \(name == "compatible" ? ".compatible" : ".strictCurrent")"
        case .integerIs(let constant):
            return "\(operand()) == Int64(\(constant))"
        }
    }

    private func canonicalStatements(
        _ operation: CanonicalOp,
        node: IRNode,
        literals: inout LiteralTable
    ) -> [String] {
        switch operation {
        case .sequence:
            return node.inputs.map { "n\($0)(&v)" }
        case .trimWhitespace:
            return ["CanonicalizationSteps.trimWhitespace(&v)"]
        case .removeWhitespace:
            return ["CanonicalizationSteps.removeWhitespace(&v)"]
        case .uppercaseASCII:
            return ["CanonicalizationSteps.uppercaseASCII(&v)"]
        case .removeChars(let set):
            return ["CanonicalizationSteps.removeChars(&v, GeneratedLiterals.\(literals.name(scalars: set)))"]
        case .replacePrefix(let text, let replacement):
            return [
                "CanonicalizationSteps.replacePrefix(&v, GeneratedLiterals."
                    + "\(literals.name(text: text)), GeneratedLiterals.\(literals.name(text: replacement)))"
            ]
        case .prepend(let text):
            return ["CanonicalizationSteps.prepend(&v, GeneratedLiterals.\(literals.name(text: text)))"]
        case .append(let text):
            return ["CanonicalizationSteps.append(&v, GeneratedLiterals.\(literals.name(text: text)))"]
        case .insert(let index, let text):
            return [
                "CanonicalizationSteps.insert(&v, at: \(index), "
                    + "GeneratedLiterals.\(literals.name(text: text)))"
            ]
        case .leftPad(let length, let pad):
            return [
                "CanonicalizationSteps.leftPad(&v, to: \(length), with: "
                    + "\(SwiftSource.quote(String(pad))))"
            ]
        case .prependCountryIfMissing:
            return [
                "CanonicalizationSteps.prependCountryIfMissing(",
                "    &v, acceptedPrefixes: c.acceptedPrefixes, canonicalPrefix: c.canonicalPrefix)",
            ]
        case .when:
            // The predicate is evaluated against the value current at that
            // point, which is what passing `v` by value at the call does.
            var lines = ["if n\(node.inputs[0])(v) {"]
            for step in node.inputs.dropFirst() { lines.append("    n\(step)(&v)") }
            lines.append("}")
            return lines
        }
    }

    private func assertionStatements(
        _ operation: AssertionOp,
        node: IRNode,
        literals: inout LiteralTable
    ) -> [String] {
        switch operation {
        case .require(let reason, let messageKey):
            let failure = ".fail(.\(Emission.reasonCase(reason)), \(Emission.optionalString(messageKey)))"
            return ["n\(node.inputs[0])() ? .pass : \(failure)"]
        case .sequence:
            // Evaluates its operands in order and stops at the first failure,
            // whose reason code and message key become the result.
            var lines: [String] = []
            for (position, operand) in node.inputs.enumerated() {
                lines.append("let a\(position) = n\(operand)()")
                lines.append("if case .fail = a\(position) { return a\(position) }")
            }
            lines.append("return .pass")
            return lines
        }
    }

    private func checksumStatements(
        _ operation: ChecksumOp,
        node: IRNode,
        literals: inout LiteralTable
    ) -> [String] {
        func operand(_ position: Int) -> String { "n\(node.inputs[position])()" }
        switch operation {
        case .luhn(let key):
            return ["ChecksumOps.luhn(\(operand(0)), messageKey: \(Emission.optionalString(key)))"]
        case .iso7064Mod97Dash10(let key):
            return [
                "ChecksumOps.iso7064Mod97Dash10(\(operand(0)), "
                    + "messageKey: \(Emission.optionalString(key)))"
            ]
        case .compareDigit(let index, let key):
            return [
                "ChecksumOps.compareDigit(\(operand(0)), \(operand(1)), index: \(index), "
                    + "messageKey: \(Emission.optionalString(key)))"
            ]
        case .compareSlice(let start, let end, let key):
            return [
                "ChecksumOps.compareSlice(\(operand(0)), \(operand(1)), start: \(start), "
                    + "end: \(end), messageKey: \(Emission.optionalString(key)))"
            ]
        case .compareConstant(let constant, let key):
            return [
                "ChecksumOps.compareConstant(\(operand(0)), \(constant), "
                    + "messageKey: \(Emission.optionalString(key)))"
            ]
        case .unsupported(let reason, let key):
            return [".unsupported(.\(Emission.reasonCase(reason)), \(Emission.optionalString(key)))"]
        case .when:
            return ["\(operand(0)) ? \(operand(1)) : .notApplicable"]
        case .choose:
            return ["ChecksumOps.choose([\(node.inputs.map { "n\($0)()" }.joined(separator: ", "))])"]
        case .allChecks:
            return ["ChecksumOps.allChecks([\(node.inputs.map { "n\($0)()" }.joined(separator: ", "))])"]
        case .anyCheck:
            return ["ChecksumOps.anyCheck([\(node.inputs.map { "n\($0)()" }.joined(separator: ", "))])"]
        }
    }
}

/// Shared spellings between emitters.
enum Emission {
    static func reasonCase(_ reason: ReasonCode) -> String {
        switch reason {
        case .ok: "ok"
        case .empty: "empty"
        case .invalidLength: "invalidLength"
        case .invalidCharacters: "invalidCharacters"
        case .invalidFormat: "invalidFormat"
        case .invalidChecksum: "invalidChecksum"
        case .missingCountryCode: "missingCountryCode"
        case .countryMismatch: "countryMismatch"
        case .unsupportedKind: "unsupportedKind"
        case .unsupportedCountry: "unsupportedCountry"
        case .unsupportedFormat: "unsupportedFormat"
        case .unsupportedChecksum: "unsupportedChecksum"
        case .checksumNotPublished: "checksumNotPublished"
        case .notRequested: "notRequested"
        case .notRunFormatInvalid: "notRunFormatInvalid"
        case .notRunFormatUnsupported: "notRunFormatUnsupported"
        case .registryNotConfigured: "registryNotConfigured"
        case .incompatibleRuleset: "incompatibleRuleset"
        case .invalidRuleset: "invalidRuleset"
        case .inputTooLong: "inputTooLong"
        case .invalidEncoding: "invalidEncoding"
        }
    }

    static func optionalString(_ value: String?) -> String {
        value.map(SwiftSource.quote) ?? "nil"
    }
}
