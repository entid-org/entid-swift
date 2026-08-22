/// Check 25: no capability used without being declared.
///
/// Relying on `required_feature_ids` alone would not be safe against a forged
/// bundle that deliberately omits the capability matching what it uses: the
/// omission would then read as permission.
enum CapabilityUsage {
    static func check(
        declared: Set<UInt32>,
        programs: [IRProgram],
        definitions: [Definition],
        dispatchers: [Dispatcher]
    ) throws(LoadError) {
        var used: Set<UInt32> = []
        var why: [UInt32: String] = [:]

        func record(_ capability: UInt32, _ reason: @autoclosure () -> String) {
            if used.insert(capability).inserted { why[capability] = reason() }
        }

        for program in programs {
            for node in program.nodes {
                let opcode = node.operation.opcode
                for capability in opcode.capabilities { record(capability, opcode.rawValue) }
                // Capability 42 is declared by the variant, not by the
                // operation: `WEIGHTED_SUM` itself belongs to 33, and only the
                // `CUSTOM_ALPHABET` mapping reaches for 42.
                if case .integer(.weightedSum(_, _, .customAlphabet, _)) = node.operation {
                    record(Capability.checksumCustomAlphabetV1, "CHAR_MAPPING_CUSTOM_ALPHABET")
                }
            }
            if !program.captures.isEmpty || program.subject != nil {
                record(Capability.capturesAndCallsV1, "Program.captures or Program.subject_node")
            }
        }

        if !dispatchers.isEmpty {
            record(Capability.identifierDispatchV1, "IdentifierDispatcher")
        }
        if !definitions.isEmpty {
            record(Capability.coreGraphV1, "RuleBundle")
            record(Capability.profilesV1, "IdentifierDefinition.default_profile")
        }
        for definition in definitions {
            if !definition.sources.isEmpty {
                record(Capability.provenanceV1, "IdentifierDefinition.sources")
            }
            if definition.absentChecksumReason != nil {
                record(Capability.checksumTristateV1, "IdentifierDefinition.absent_checksum_reason")
            }
            // Only a stated tier requires PROVENANCE_TIER_V1. A bundle whose
            // sources all state none does not declare it, which is the
            // independence a separate id exists to give.
            if definition.sources.contains(where: { $0.tier != nil }) {
                record(Capability.provenanceTierV1, "Source.tier")
            }
        }

        let undeclared = used.subtracting(declared).sorted()
        guard undeclared.isEmpty else {
            let detail = undeclared
                .map { "\(Capability.name(of: $0)) (used by \(why[$0] ?? "the bundle"))" }
                .joined(separator: ", ")
            throw .invalidRuleset("capability used without being declared: \(detail)")
        }
    }
}
