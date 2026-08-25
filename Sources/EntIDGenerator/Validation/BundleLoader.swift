internal import EntIDWire

internal import struct Foundation.Data

/// The twenty five load checks of `ir.md` section 10, in the order they are
/// stated.
///
/// The generator refuses to emit anything unless every one of them passes. A
/// size, structural, arithmetic or graph violation is `invalid_ruleset`; an
/// unsupported `format_version` and an unknown capability id are
/// `incompatible_ruleset`.
package enum RuleBundleLoader {
    /// The only structural IR version this generator understands.
    package static let supportedFormatVersion: UInt32 = 1

    package static func load(_ bytes: [UInt8]) throws(LoadError) -> LoadedBundle {
        // 1. binary size at most 16 MiB.
        guard bytes.count <= Limits.maximumBundleBytes else {
            throw .invalidRuleset("bundle is \(bytes.count) bytes, beyond \(Limits.maximumBundleBytes)")
        }

        // 2. complete Protobuf decoding. Decoding proves the bytes parse and
        //    nothing more: an unresolved opcode is carried to check 10, an
        //    unknown field to check 5, and an unrecognised enum value to the
        //    check that owns its field.
        let wire: Libbusinessid_Ir_V1_RuleBundle
        do {
            wire = try Libbusinessid_Ir_V1_RuleBundle(serializedBytes: Data(bytes))
        } catch {
            throw .invalidRuleset("bundle does not decode as a RuleBundle")
        }

        // 3. supported `format_version`.
        guard wire.formatVersion == supportedFormatVersion else {
            throw .incompatibleRuleset(
                "format_version \(wire.formatVersion) is not supported; this engine implements "
                    + "\(supportedFormatVersion)"
            )
        }

        // 4. every `required_feature_ids` entry known, strictly ascending.
        for identifier in wire.requiredFeatureIds where !Capability.known.contains(identifier) {
            throw .incompatibleRuleset("capability \(identifier) is not implemented by this engine")
        }
        guard zip(wire.requiredFeatureIds, wire.requiredFeatureIds.dropFirst()).allSatisfy({ $0 < $1 })
        else {
            throw .invalidRuleset("required_feature_ids is not strictly ascending")
        }

        // 5. absence of any unknown field at any depth.
        if let path = UnknownFieldScan.run(wire) {
            throw .invalidRuleset("unknown Protobuf field at \(path)")
        }

        // 6. `rules_version` non empty, at most 64 bytes, ASCII letters,
        //    digits, dot, dash and underscore. The value reaches generated
        //    sources, manifests and logs.
        guard TokenShape.isWellFormedRulesVersion(wire.rulesVersion) else {
            throw .invalidRuleset("rules_version is empty, too long or holds a forbidden character")
        }

        // 7. `source_digest` of exactly 32 bytes.
        guard wire.sourceDigest.count == 32 else {
            throw .invalidRuleset("source_digest is \(wire.sourceDigest.count) bytes, not 32")
        }

        let programs = try loadPrograms(wire)
        var programIndexByID: [UInt32: Int] = [:]
        for (index, program) in programs.enumerated() { programIndexByID[program.id] = index }

        // 16 needs to know which programs a dispatcher pre-canonicalizes and
        // which canonicalizers a GLOBAL definition uses. Both are plain field
        // reads; nothing is trusted before its own check runs.
        let preCanonicalizationIDs = Set(wire.dispatchers.map(\.preCanonicalizationProgram))
        let globalCanonicalizationIDs = Set(
            wire.identifiers.filter { !$0.hasCountryCode }.map(\.canonicalizationProgram)
        )
        for program in programs {
            try ProgramShape.check(
                program,
                isPreCanonicalization: preCanonicalizationIDs.contains(program.id),
                isGlobalCanonicalizer: globalCanonicalizationIDs.contains(program.id)
            )
        }

        let definitions = try loadDefinitions(wire, programIndexByID: programIndexByID)
        let dispatchers = try loadDispatchers(wire, definitions: definitions, programs: programIndexByID)

        // 24. call graph acyclic, typed and of static depth at most 32.
        try CallGraph.check(programs: programs, indexByID: programIndexByID)

        // 25. no capability used without being declared.
        try CapabilityUsage.check(
            declared: Set(wire.requiredFeatureIds),
            programs: programs,
            definitions: definitions,
            dispatchers: dispatchers
        )

        let expansion = try Expansion.profile(of: programs)

        return LoadedBundle(
            formatVersion: wire.formatVersion,
            rulesVersion: wire.rulesVersion,
            requiredFeatures: wire.requiredFeatureIds,
            sourceDigest: Array(wire.sourceDigest),
            programs: programs,
            programIndexByID: programIndexByID,
            definitions: definitions,
            dispatchers: dispatchers,
            expansion: expansion
        )
    }

    // MARK: - Programs, checks 8 to 15

    private static func loadPrograms(
        _ wire: Libbusinessid_Ir_V1_RuleBundle
    ) throws(LoadError) -> [IRProgram] {
        // 8. program ids unique and non zero, program kinds specified. The
        //    serialization order of section 9 is ascending id, and two equal
        //    sort keys are a rejected duplicate rather than a tie broken by the
        //    input order.
        var previousID: UInt32?
        var totalNodes = 0
        var programs: [IRProgram] = []
        programs.reserveCapacity(wire.programs.count)

        for raw in wire.programs {
            guard raw.id != 0 else { throw .invalidRuleset("a program carries id zero") }
            if let previous = previousID {
                guard previous < raw.id else {
                    throw .invalidRuleset("programs are not sorted by strictly ascending id")
                }
            }
            previousID = raw.id
            guard let kind = ProgramKind(wire: raw.kind) else {
                throw .invalidRuleset("program \(raw.id) declares no known kind")
            }

            // 9. node count within the per program and total limits.
            guard raw.nodes.count <= Limits.maximumNodesPerProgram else {
                throw .invalidRuleset(
                    "program \(raw.id) holds \(raw.nodes.count) nodes, beyond "
                        + "\(Limits.maximumNodesPerProgram)"
                )
            }
            totalNodes += raw.nodes.count
            guard totalNodes <= Limits.maximumTotalNodes else {
                throw .invalidRuleset("the bundle holds more than \(Limits.maximumTotalNodes) nodes")
            }

            // 10 to 12, per node, then the operand types of check 11, which
            // only the already lowered earlier nodes can answer.
            var nodes: [IRNode] = []
            nodes.reserveCapacity(raw.nodes.count)
            for (index, rawNode) in raw.nodes.enumerated() {
                let node = try NodeLowering(programID: raw.id, nodeIndex: index).lower(rawNode)
                try checkOperandTypes(node, earlier: nodes, programID: raw.id, nodeIndex: index)
                nodes.append(node)
            }

            // 13, the part that reads a whole expression rather than one node.
            try LengthAnalysis.check(nodes: nodes, programID: raw.id)

            // 15. root, subject and capture nodes inside the program and
            //     correctly typed. It runs before check 14 because the roots
            //     check 14 counts from are exactly what this validates; both
            //     report `invalid_ruleset`, so the order is not observable.
            let root = Int(raw.rootNode)
            guard root < nodes.count else {
                throw .invalidRuleset("program \(raw.id) root node \(root) is outside the program")
            }
            var subject: Int?
            if raw.hasSubjectNode {
                let index = Int(raw.subjectNode)
                guard index < nodes.count else {
                    throw .invalidRuleset("program \(raw.id) subject node \(index) is outside the program")
                }
                guard nodes[index].outputType == .string else {
                    throw .invalidRuleset("program \(raw.id) subject node does not produce a string")
                }
                // `subject()` is what the subject node produces, so a subject
                // node that reads `subject()` defines it in terms of itself.
                // `ir.md` does not state this; it is reported upstream in
                // SPEC-ISSUES.md. An engine that emits the subject node as a
                // function would recur forever, and an interpreter would
                // exhaust its budget, so no reading of the IR makes it usable.
                if let offender = firstSubjectRead(from: index, in: nodes) {
                    throw .invalidRuleset(
                        "program \(raw.id) subject node reads subject() at node \(offender), "
                            + "which defines it in terms of itself"
                    )
                }
                subject = index
            }
            guard raw.captures.count <= Limits.maximumCapturesPerFormat else {
                throw .invalidRuleset(
                    "program \(raw.id) declares \(raw.captures.count) captures, beyond "
                        + "\(Limits.maximumCapturesPerFormat)"
                )
            }
            var captures: [IRProgram.Capture] = []
            var capturedNames: Set<String> = []
            for capture in raw.captures {
                let index = Int(capture.node)
                guard index < nodes.count else {
                    throw .invalidRuleset("program \(raw.id) capture node \(index) is outside the program")
                }
                guard nodes[index].outputType == .string else {
                    throw .invalidRuleset("program \(raw.id) capture \(capture.name) does not name a string")
                }
                guard !capture.name.isEmpty, capturedNames.insert(capture.name).inserted else {
                    throw .invalidRuleset("program \(raw.id) declares an empty or duplicate capture name")
                }
                captures.append(IRProgram.Capture(name: capture.name, node: index))
            }

            programs.append(
                IRProgram(
                    id: raw.id, kind: kind, nodes: nodes, root: root, captures: captures, subject: subject
                )
            )
        }
        return programs
    }

    /// The first node of the subtree rooted at `index` that reads `subject()`.
    private static func firstSubjectRead(from index: Int, in nodes: [IRNode]) -> Int? {
        var stack = [index]
        var seen: Set<Int> = []
        while let current = stack.popLast() {
            guard seen.insert(current).inserted else { continue }
            if case .string(.subject) = nodes[current].operation { return current }
            stack.append(contentsOf: nodes[current].inputs)
        }
        return nil
    }

    /// Check 11, operand types.
    private static func checkOperandTypes(
        _ node: IRNode,
        earlier: [IRNode],
        programID: UInt32,
        nodeIndex: Int
    ) throws(LoadError) {
        let spec = node.operation.opcode.operands
        for (position, operand) in node.inputs.enumerated() {
            let expected = position < spec.fixed.count ? spec.fixed[position] : spec.repeatedType
            guard let expected else {
                throw .invalidRuleset("program \(programID) node \(nodeIndex): unexpected operand")
            }
            guard earlier[operand].outputType == expected else {
                throw .invalidRuleset(
                    "program \(programID) node \(nodeIndex): operand \(position) is "
                        + "\(earlier[operand].outputType.rawValue), \(expected.rawValue) expected"
                )
            }
        }
    }

    // MARK: - Definitions, checks 17 and 18

    private static func loadDefinitions(
        _ wire: Libbusinessid_Ir_V1_RuleBundle,
        programIndexByID: [UInt32: Int]
    ) throws(LoadError) -> [Definition] {
        guard wire.identifiers.count <= Limits.maximumIdentifiers else {
            throw .invalidRuleset("the bundle holds more than \(Limits.maximumIdentifiers) identifiers")
        }

        var seenIDs: Set<UInt32> = []
        var previousKey: (kind: String, country: String?)?
        var definitions: [Definition] = []

        for raw in wire.identifiers {
            guard raw.id != 0, seenIDs.insert(raw.id).inserted else {
                throw .invalidRuleset("identifier id \(raw.id) is zero or repeated")
            }
            guard TokenShape.isWellFormedKind(raw.kind) else {
                throw .invalidRuleset("identifier \(raw.id) declares a malformed kind")
            }
            var country: String?
            if raw.hasCountryCode {
                // Absence means GLOBAL. The empty string and the literal
                // "GLOBAL" are invalid, so that one notion has one encoding.
                guard TokenShape.isWellFormedCountry(raw.countryCode), raw.countryCode != "GLOBAL" else {
                    throw .invalidRuleset("identifier \(raw.id) declares a malformed country code")
                }
                country = raw.countryCode
            }

            // Serialization order: kind, then GLOBAL first, then country code.
            if let previous = previousKey {
                guard isOrdered(previous, (raw.kind, country)) else {
                    throw .invalidRuleset("identifiers are not sorted by kind then GLOBAL then country")
                }
            }
            previousKey = (raw.kind, country)

            guard raw.defaultProfile == "compatible" || raw.defaultProfile == "strict_current" else {
                throw .invalidRuleset("identifier \(raw.id) declares an unknown default profile")
            }

            for (identifier, expected) in [
                (raw.canonicalizationProgram, ProgramKind.canonicalization),
                (raw.formatProgram, ProgramKind.format),
            ] {
                try requireProgram(identifier, of: expected, in: wire, indexByID: programIndexByID)
            }

            // 18. exactly one checksum program or one absence reason.
            var checksumProgram: UInt32?
            var absentReason: ReasonCode?
            switch (raw.hasChecksumProgram, raw.hasAbsentChecksumReason) {
            case (true, false):
                try requireProgram(
                    raw.checksumProgram, of: .checksum, in: wire, indexByID: programIndexByID
                )
                checksumProgram = raw.checksumProgram
            case (false, true):
                guard let code = ReasonCode(wire: raw.absentChecksumReason),
                    ReasonCode.absentChecksum.contains(code)
                else {
                    throw .invalidRuleset("identifier \(raw.id) declares an unusable absent checksum reason")
                }
                absentReason = code
            case (true, true), (false, false):
                throw .invalidRuleset(
                    "identifier \(raw.id) must declare exactly one of a checksum program or an absence reason"
                )
            }

            definitions.append(
                Definition(
                    id: raw.id,
                    kind: raw.kind,
                    countryCode: country,
                    canonicalizationProgram: raw.canonicalizationProgram,
                    formatProgram: raw.formatProgram,
                    checksumProgram: checksumProgram,
                    defaultProfile: raw.defaultProfile,
                    sources: try loadSources(raw),
                    absentChecksumReason: absentReason
                )
            )
        }
        return definitions
    }

    private static func isOrdered(
        _ lhs: (kind: String, country: String?),
        _ rhs: (kind: String, country: String?)
    ) -> Bool {
        if lhs.kind != rhs.kind { return precedesByUTF8(lhs.kind, rhs.kind) }
        switch (lhs.country, rhs.country) {
        case (nil, nil): return false  // two GLOBAL definitions of one kind: a duplicate
        case (nil, _): return true
        case (_, nil): return false
        case (let left?, let right?): return precedesByUTF8(left, right)
        }
    }

    private static func requireProgram(
        _ identifier: UInt32,
        of kind: ProgramKind,
        in wire: Libbusinessid_Ir_V1_RuleBundle,
        indexByID: [UInt32: Int]
    ) throws(LoadError) {
        guard let index = indexByID[identifier] else {
            throw .invalidRuleset("program \(identifier) is referenced but not declared")
        }
        guard ProgramKind(wire: wire.programs[index].kind) == kind else {
            throw .invalidRuleset("program \(identifier) is used as a \(kind.rawValue) it is not")
        }
    }

    /// `PROVENANCE_V1`: sources sorted by the UTF-8 bytes of their id, and
    /// every rule able to reject an input carries at least one.
    private static func loadSources(
        _ raw: Libbusinessid_Ir_V1_IdentifierDefinition
    ) throws(LoadError) -> [Source] {
        guard !raw.sources.isEmpty else {
            throw .invalidRuleset("identifier \(raw.id) is able to reject an input and cites no source")
        }
        var sources: [Source] = []
        var previous: String?
        for source in raw.sources {
            guard !source.id.isEmpty else {
                throw .invalidRuleset("identifier \(raw.id) carries a source without id")
            }
            if let previous {
                guard precedesByUTF8(previous, source.id) else {
                    throw .invalidRuleset("identifier \(raw.id) sources are not sorted by ascending id")
                }
            }
            previous = source.id
            guard let stated = SourceTier.recognised(wire: source.tier) else {
                throw .invalidRuleset("identifier \(raw.id) source \(source.id) states an unknown tier")
            }
            sources.append(
                Source(
                    id: source.id,
                    url: source.url,
                    authority: source.authority,
                    title: source.title,
                    accessedAt: source.accessedAt,
                    jurisdiction: source.jurisdiction,
                    language: source.language,
                    notes: source.notes,
                    licenseOrTerms: source.licenseOrTerms,
                    archiveURL: source.hasArchiveURL ? source.archiveURL : nil,
                    tier: stated.tier
                )
            )
        }
        return sources
    }

    // MARK: - Dispatchers, checks 19 to 23

    private static func loadDispatchers(
        _ wire: Libbusinessid_Ir_V1_RuleBundle,
        definitions: [Definition],
        programs: [UInt32: Int]
    ) throws(LoadError) -> [Dispatcher] {
        var definitionByID: [UInt32: Definition] = [:]
        for definition in definitions { definitionByID[definition.id] = definition }

        // 19. dispatcher kinds and aliases globally unique, sorted, never
        //     ambiguous. Kinds and aliases share one space: an alias that
        //     equals a canonical kind would route two ways.
        var kindSpace: Set<String> = []
        var previousKind: String?
        var dispatchers: [Dispatcher] = []
        var claimedDefinitions: [UInt32: String] = [:]

        for raw in wire.dispatchers {
            guard TokenShape.isWellFormedKind(raw.kind) else {
                throw .invalidRuleset("dispatcher \(raw.kind) declares a malformed kind")
            }
            if let previous = previousKind {
                guard precedesByUTF8(previous, raw.kind) else {
                    throw .invalidRuleset("dispatchers are not sorted by ascending kind")
                }
            }
            previousKind = raw.kind
            guard kindSpace.insert(raw.kind).inserted else {
                throw .invalidRuleset("kind \(raw.kind) is claimed twice")
            }
            var previousAlias: String?
            for alias in raw.kindAliases {
                guard TokenShape.isWellFormedKind(alias) else {
                    throw .invalidRuleset("dispatcher \(raw.kind) declares a malformed alias")
                }
                if let previous = previousAlias {
                    guard precedesByUTF8(previous, alias) else {
                        throw .invalidRuleset("dispatcher \(raw.kind) aliases are not sorted")
                    }
                }
                previousAlias = alias
                guard kindSpace.insert(alias).inserted else {
                    throw .invalidRuleset("kind alias \(alias) is claimed twice")
                }
            }

            try requireProgram(
                raw.preCanonicalizationProgram, of: .canonicalization, in: wire, indexByID: programs
            )

            let targets = try loadTargets(raw, definitions: definitionByID, claimed: &claimedDefinitions)
            let aliases = try loadCountryAliases(raw, targets: targets)

            dispatchers.append(
                Dispatcher(
                    kind: raw.kind,
                    kindAliases: raw.kindAliases,
                    preCanonicalizationProgram: raw.preCanonicalizationProgram,
                    countryAliases: aliases,
                    targets: targets
                )
            )
        }

        // 23. every definition referenced by exactly one dispatch target.
        for definition in definitions where claimedDefinitions[definition.id] == nil {
            throw .invalidRuleset("identifier \(definition.id) is referenced by no dispatch target")
        }
        return dispatchers
    }

    private static func loadTargets(
        _ raw: Libbusinessid_Ir_V1_IdentifierDispatcher,
        definitions: [UInt32: Definition],
        claimed: inout [UInt32: String]
    ) throws(LoadError) -> [DispatchTarget] {
        var targets: [DispatchTarget] = []
        var previousCountry: String??
        var prefixOwners: Set<String> = []
        var unprefixedTargets = 0
        var hasGlobalTarget = false

        for raw2 in raw.targets {
            var country: String?
            if raw2.hasCountryCode {
                guard TokenShape.isWellFormedCountry(raw2.countryCode), raw2.countryCode != "GLOBAL" else {
                    throw .invalidRuleset("dispatcher \(raw.kind) declares a malformed target country")
                }
                country = raw2.countryCode
            } else {
                hasGlobalTarget = true
            }

            // 21. targets sorted, unique per country: GLOBAL first, then
            //     country code ascending.
            if let previous = previousCountry {
                guard isOrdered((raw.kind, previous), (raw.kind, country)) else {
                    throw .invalidRuleset("dispatcher \(raw.kind) targets are not sorted")
                }
            }
            previousCountry = .some(country)

            var previousPrefix: String?
            for prefix in raw2.acceptedPrefixes {
                guard TokenShape.isWellFormedPrefix(prefix) else {
                    throw .invalidRuleset("dispatcher \(raw.kind) declares a malformed prefix")
                }
                if let previous = previousPrefix {
                    guard precedesByUTF8(previous, prefix) else {
                        throw .invalidRuleset("dispatcher \(raw.kind) prefixes are not sorted")
                    }
                }
                previousPrefix = prefix
                // A prefix value claimed by two targets makes resolution depend
                // on the serialization order, which nothing may depend on.
                guard prefixOwners.insert(prefix).inserted else {
                    throw .invalidRuleset("dispatcher \(raw.kind) prefix \(prefix) is claimed twice")
                }
            }
            var canonicalPrefix: String?
            if raw2.hasCanonicalPrefix {
                guard TokenShape.isWellFormedPrefix(raw2.canonicalPrefix) else {
                    throw .invalidRuleset("dispatcher \(raw.kind) declares a malformed canonical prefix")
                }
                canonicalPrefix = raw2.canonicalPrefix
            }

            // 22. GLOBAL targets alone, without prefix and without country
            //     alias.
            if country == nil {
                guard raw2.acceptedPrefixes.isEmpty, canonicalPrefix == nil else {
                    throw .invalidRuleset("dispatcher \(raw.kind) GLOBAL target declares a prefix")
                }
                guard raw.countryAliases.isEmpty else {
                    throw .invalidRuleset("dispatcher \(raw.kind) mixes a GLOBAL target and country aliases")
                }
            }

            if raw2.allowUnprefixedWithoutCountry { unprefixedTargets += 1 }

            // 23, the half a target owns: it references a definition of its own
            // kind and country, and no other target references it.
            guard let definition = definitions[raw2.identifierDefinitionID] else {
                throw .invalidRuleset("dispatcher \(raw.kind) targets an unknown identifier")
            }
            guard definition.kind == raw.kind, definition.countryCode == country else {
                throw .invalidRuleset(
                    "dispatcher \(raw.kind) targets identifier \(definition.id) of another kind or country"
                )
            }
            guard claimed.updateValue(raw.kind, forKey: definition.id) == nil else {
                throw .invalidRuleset("identifier \(definition.id) is referenced by two dispatch targets")
            }

            targets.append(
                DispatchTarget(
                    countryCode: country,
                    acceptedPrefixes: raw2.acceptedPrefixes,
                    canonicalPrefix: canonicalPrefix,
                    identifierDefinitionID: raw2.identifierDefinitionID,
                    allowUnprefixedWithoutCountry: raw2.allowUnprefixedWithoutCountry
                )
            )
        }

        guard !hasGlobalTarget || targets.count == 1 else {
            throw .invalidRuleset("dispatcher \(raw.kind) mixes a GLOBAL target with country targets")
        }
        // Step 8 of dispatch selects "the single allow_unprefixed_without_country
        // target": two of them would make that step ambiguous.
        guard unprefixedTargets <= 1 else {
            throw .invalidRuleset(
                "dispatcher \(raw.kind) declares \(unprefixedTargets) unprefixed targets"
            )
        }
        return targets
    }

    /// Check 20: country aliases sorted, unique, never self mapping and never
    /// shadowing a target.
    private static func loadCountryAliases(
        _ raw: Libbusinessid_Ir_V1_IdentifierDispatcher,
        targets: [DispatchTarget]
    ) throws(LoadError) -> [Dispatcher.CountryAlias] {
        let targetCountries = Set(targets.compactMap(\.countryCode))
        var aliases: [Dispatcher.CountryAlias] = []
        var previous: String?

        for alias in raw.countryAliases {
            guard TokenShape.isWellFormedCountry(alias.alias),
                TokenShape.isWellFormedCountry(alias.countryCode)
            else {
                throw .invalidRuleset("dispatcher \(raw.kind) declares a malformed country alias")
            }
            if let previous {
                guard precedesByUTF8(previous, alias.alias) else {
                    throw .invalidRuleset("dispatcher \(raw.kind) country aliases are not sorted")
                }
            }
            previous = alias.alias
            guard alias.alias != alias.countryCode else {
                throw .invalidRuleset("dispatcher \(raw.kind) maps country \(alias.alias) to itself")
            }
            guard !targetCountries.contains(alias.alias) else {
                throw .invalidRuleset(
                    "dispatcher \(raw.kind) alias \(alias.alias) shadows a target of the same name"
                )
            }
            aliases.append(
                Dispatcher.CountryAlias(alias: alias.alias, countryCode: alias.countryCode)
            )
        }
        return aliases
    }
}
