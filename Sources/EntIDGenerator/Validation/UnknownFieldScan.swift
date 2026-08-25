internal import EntIDWire

/// Check 5: absence of any unknown field at any depth.
///
/// The walk is written out rather than driven by reflection so that a message
/// added to the schema without a matching branch here is a compile error, not
/// a silently unscanned subtree.
///
/// It runs *after* the version and capability checks, and the order carries a
/// meaning. A bundle built against a later version holds fields this generator
/// has never heard of; reporting those as unknown fields would call a
/// legitimate version gap a forged bundle.
enum UnknownFieldScan {
    /// The path of the first message carrying an unknown field, or `nil`.
    static func run(_ bundle: Entid_Ir_V1_RuleBundle) -> String? {
        if !bundle.unknownFields.data.isEmpty { return "RuleBundle" }

        for (index, definition) in bundle.identifiers.enumerated() {
            let path = "identifiers[\(index)]"
            if !definition.unknownFields.data.isEmpty { return path }
            for (sourceIndex, source) in definition.sources.enumerated() {
                guard source.unknownFields.data.isEmpty else { return "\(path).sources[\(sourceIndex)]" }
            }
        }

        for (index, dispatcher) in bundle.dispatchers.enumerated() {
            let path = "dispatchers[\(index)]"
            if !dispatcher.unknownFields.data.isEmpty { return path }
            for (aliasIndex, alias) in dispatcher.countryAliases.enumerated() {
                guard alias.unknownFields.data.isEmpty else {
                    return "\(path).country_aliases[\(aliasIndex)]"
                }
            }
            for (targetIndex, target) in dispatcher.targets.enumerated() {
                guard target.unknownFields.data.isEmpty else { return "\(path).targets[\(targetIndex)]" }
            }
        }

        for (index, program) in bundle.programs.enumerated() {
            let path = "programs[\(index)]"
            if !program.unknownFields.data.isEmpty { return path }
            for (captureIndex, capture) in program.captures.enumerated() {
                guard capture.unknownFields.data.isEmpty else {
                    return "\(path).captures[\(captureIndex)]"
                }
            }
            for (nodeIndex, node) in program.nodes.enumerated() {
                if !node.unknownFields.data.isEmpty { return "\(path).nodes[\(nodeIndex)]" }
                if let field = operationCarriesUnknownField(node.operation) {
                    return "\(path).nodes[\(nodeIndex)].\(field)"
                }
            }
        }

        return nil
    }

    private static func operationCarriesUnknownField(
        _ operation: Entid_Ir_V1_Node.OneOf_Operation?
    ) -> String? {
        switch operation {
        case .stringOperation(let payload):
            payload.unknownFields.data.isEmpty ? nil : "string_operation"
        case .integerOperation(let payload):
            payload.unknownFields.data.isEmpty ? nil : "integer_operation"
        case .predicateOperation(let payload):
            payload.unknownFields.data.isEmpty ? nil : "predicate_operation"
        case .canonicalizationOperation(let payload):
            payload.unknownFields.data.isEmpty ? nil : "canonicalization_operation"
        case .assertionOperation(let payload):
            payload.unknownFields.data.isEmpty ? nil : "assertion_operation"
        case .checksumOperation(let payload):
            payload.unknownFields.data.isEmpty ? nil : "checksum_operation"
        case .callOperation(let payload):
            payload.unknownFields.data.isEmpty ? nil : "call_operation"
        case .none:
            nil
        }
    }
}
