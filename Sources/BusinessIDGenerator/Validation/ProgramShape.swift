/// Check 16: accepted root per kind, `WHEN` only inside `CHOOSE`, and a
/// pre-canonicalization program restricted to its five permitted operations.
enum ProgramShape {
    static func check(
        _ program: IRProgram,
        isPreCanonicalization: Bool,
        isGlobalCanonicalizer: Bool
    ) throws(LoadError) {
        func reject(_ detail: String) -> LoadError {
            .invalidRuleset("program \(program.id): \(detail)")
        }

        let rootOperation = program.nodes[program.root].operation

        switch program.kind {
        case .canonicalization:
            guard case .canonical(.sequence) = rootOperation else {
                throw reject("a canonicalization program roots at SEQUENCE and nothing else")
            }
            // A canonicalization program never declares a subject and never
            // declares a capture.
            guard program.subject == nil, program.captures.isEmpty else {
                throw reject("a canonicalization program declares no subject and no capture")
            }

        case .format:
            guard case .assertion(.sequence) = rootOperation else {
                throw reject("a format program roots at an assertion SEQUENCE and nothing else")
            }

        case .checksum:
            guard program.nodes[program.root].outputType == .checksumOutcome else {
                throw reject("a checksum program roots at a checksum outcome")
            }
            // A `WHEN` at the root would expose its non applicable state, which
            // is only ever observable as a branch of `CHOOSE`.
            guard case .checksum(.when) = rootOperation else { break }
            throw reject("a checksum program never roots at a WHEN branch")
        }

        for (index, node) in program.nodes.enumerated() {
            try checkCategory(
                node,
                in: program,
                at: index,
                isPreCanonicalization: isPreCanonicalization,
                isGlobalCanonicalizer: isGlobalCanonicalizer
            )
        }

        // `CHECKSUM_OP_KIND_WHEN` is accepted only as a direct operand of
        // `CHOOSE`.
        var readByChoose = [Bool](repeating: false, count: program.nodes.count)
        var readByAnythingElse = [Bool](repeating: false, count: program.nodes.count)
        for node in program.nodes {
            let fromChoose: Bool
            if case .checksum(.choose) = node.operation { fromChoose = true } else { fromChoose = false }
            for operand in node.inputs {
                if fromChoose { readByChoose[operand] = true } else { readByAnythingElse[operand] = true }
            }
        }
        for (index, node) in program.nodes.enumerated() {
            guard case .checksum(.when) = node.operation else { continue }
            guard readByChoose[index], !readByAnythingElse[index] else {
                throw reject("node \(index) is a WHEN branch outside a CHOOSE")
            }
        }
    }

    private static func checkCategory(
        _ node: IRNode,
        in program: IRProgram,
        at index: Int,
        isPreCanonicalization: Bool,
        isGlobalCanonicalizer: Bool
    ) throws(LoadError) {
        func reject(_ detail: String) -> LoadError {
            .invalidRuleset("program \(program.id) node \(index): \(detail)")
        }

        // A pre-canonicalization program is restricted to SEQUENCE,
        // TRIM_WHITESPACE, REMOVE_WHITESPACE, UPPERCASE_ASCII and
        // REMOVE_CHARS. It can never add, replace or interpret a prefix.
        if isPreCanonicalization {
            switch node.operation {
            case .canonical(.sequence), .canonical(.trimWhitespace), .canonical(.removeWhitespace),
                .canonical(.uppercaseASCII), .canonical(.removeChars):
                return
            default:
                throw reject(
                    "\(node.operation.opcode.rawValue) is not one of the five pre-canonicalization steps"
                )
            }
        }

        switch program.kind {
        case .canonicalization:
            switch node.operation {
            case .string(.subject):
                throw reject("subject() is forbidden in a canonicalization program")
            case .canonical(.prependCountryIfMissing) where isGlobalCanonicalizer:
                throw reject("prepend_country_if_missing is forbidden in a GLOBAL canonicalizer")
            case .string, .predicate, .canonical:
                return
            case .integer, .assertion, .checksum, .call:
                throw reject("\(node.operation.opcode.rawValue) has no place in a canonicalization program")
            }

        case .format:
            switch node.operation {
            case .string, .predicate, .assertion, .call(.format):
                return
            case .integer, .canonical, .checksum, .call(.checksum):
                throw reject("\(node.operation.opcode.rawValue) has no place in a format program")
            }

        case .checksum:
            switch node.operation {
            case .string, .predicate, .integer, .checksum, .call(.checksum):
                return
            case .canonical, .assertion, .call(.format):
                throw reject("\(node.operation.opcode.rawValue) has no place in a checksum program")
            }
        }
    }
}
