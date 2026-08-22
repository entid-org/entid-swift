/// A bundle that passed the twenty five load checks of `ir.md` section 10.
///
/// Nothing here is optional in the "might be malformed" sense: every index has
/// been resolved, every enum recognised, every bound proved. The emitter reads
/// this and never the decoded Protobuf message.
package struct LoadedBundle: Sendable {
    package let formatVersion: UInt32
    package let rulesVersion: String
    package let requiredFeatures: [UInt32]
    package let sourceDigest: [UInt8]
    /// Programs in bundle order, which check 8 proved is ascending by id.
    package let programs: [IRProgram]
    /// Position of a program in `programs`, by its bundle id.
    package let programIndexByID: [UInt32: Int]
    package let definitions: [Definition]
    package let dispatchers: [Dispatcher]
    /// The check 14 measurement, kept so the generator can publish it.
    package let expansion: ExpansionProfile

    package func program(id: UInt32) -> IRProgram? {
        programIndexByID[id].map { programs[$0] }
    }
}

/// One operation of a program, with its operands resolved to node indices of
/// the same program, all strictly lower than its own.
package struct IRNode: Sendable, Hashable {
    package let outputType: ValueType
    package let inputs: [Int]
    package let operation: Operation
}

package struct IRProgram: Sendable {
    package let id: UInt32
    package let kind: ProgramKind
    package let nodes: [IRNode]
    package let root: Int
    /// Named captures of a format program. Metadata: a capture reference was
    /// already lowered to a direct node reference, so this list exists for
    /// diagnostics, for the per format capture limit and for check 14.
    package let captures: [Capture]
    package let subject: Int?

    package struct Capture: Sendable, Hashable {
        package let name: String
        package let node: Int
    }
}

package struct Source: Sendable, Hashable {
    package let id: String
    package let url: String
    package let authority: String
    package let title: String
    package let accessedAt: String
    package let jurisdiction: String
    package let language: String
    package let notes: String
    package let licenseOrTerms: String
    package let archiveURL: String?
    /// Absent when the source states no tier. `tier` is not `optional` in the
    /// schema, so an omitted field and `SOURCE_TIER_UNSPECIFIED` are the same
    /// bytes: only a stated tier requires `PROVENANCE_TIER_V1`.
    package let tier: SourceTier?
}

package struct Definition: Sendable {
    package let id: UInt32
    package let kind: String
    /// Absent means GLOBAL.
    package let countryCode: String?
    package let canonicalizationProgram: UInt32
    package let formatProgram: UInt32
    package let checksumProgram: UInt32?
    package let defaultProfile: String
    package let sources: [Source]
    /// Reason reported when `checksumProgram` is absent. Exactly one of the two
    /// is present, which is check 18.
    package let absentChecksumReason: ReasonCode?
}

package struct Dispatcher: Sendable {
    package let kind: String
    package let kindAliases: [String]
    package let preCanonicalizationProgram: UInt32
    package let countryAliases: [CountryAlias]
    package let targets: [DispatchTarget]

    package struct CountryAlias: Sendable, Hashable {
        package let alias: String
        package let countryCode: String
    }
}

package struct DispatchTarget: Sendable {
    /// Absent means the GLOBAL target.
    package let countryCode: String?
    package let acceptedPrefixes: [String]
    package let canonicalPrefix: String?
    package let identifierDefinitionID: UInt32
    package let allowUnprefixedWithoutCountry: Bool
}

/// What check 14 measured, published by the generator so that two engines can
/// compare a number no conformance case can establish.
package struct ExpansionProfile: Sendable, Hashable {
    package let programCount: Int
    package let totalInstances: Int
    package let worstProgramID: UInt32
    package let worstInstances: Int
    package let worstNodeCount: Int

    /// The line the generator publishes. Two engines can only agree on this
    /// count by comparing it: no conformance case reaches it.
    package var summary: String {
        "\(programCount) programs, \(totalInstances) instances, "
            + "worst program \(worstProgramID) at \(worstInstances)"
    }
}
