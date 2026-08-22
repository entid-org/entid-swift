internal import BusinessIDWire

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
    static func run(_ bundle: Libbusinessid_Ir_V1_RuleBundle) -> String? {
        if !bundle.unknownFields.data.isEmpty { return "RuleBundle" }

        for (index, definition) in bundle.identifiers.enumerated() {
            if !definition.unknownFields.data.isEmpty { return "identifiers[\(index)]" }
            for (sourceIndex, source) in definition.sources.enumerated() where
                !source.unknownFields.data.isEmpty
            {
                return "identifiers[\(index)].sources[\(sourceIndex)]"
            }
        }

        for (index, dispatcher) in bundle.dispatchers.enumerated() {
            if !dispatcher.unknownFields.data.isEmpty { return "dispatchers[\(index)]" }
            for (aliasIndex, alias) in dispatcher.countryAliases.enumerated() where
                !alias.unknownFields.data.isEmpty
            {
                return "dispatchers[\(index)].country_aliases[\(aliasIndex)]"
            }
            for (targetIndex, target) in dispatcher.targets.enumerated() where
                !target.unknownFields.data.isEmpty
            {
                return "dispatchers[\(index)].targets[\(targetIndex)]"
            }
        }

        for (index, program) in bundle.programs.enumerated() {
            if !program.unknownFields.data.isEmpty { return "programs[\(index)]" }
            for (captureIndex, capture) in program.captures.enumerated() where
                !capture.unknownFields.data.isEmpty
            {
                return "programs[\(index)].captures[\(captureIndex)]"
            }
            for (nodeIndex, node) in program.nodes.enumerated() {
                if !node.unknownFields.data.isEmpty { return "programs[\(index)].nodes[\(nodeIndex)]" }
                if let where_ = operationCarriesUnknownField(node.operation) {
                    return "programs[\(index)].nodes[\(nodeIndex)].\(where_)"
                }
            }
        }

        return nil
    }

    private static func operationCarriesUnknownField(
        _ operation: Libbusinessid_Ir_V1_Node.OneOf_Operation?
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
