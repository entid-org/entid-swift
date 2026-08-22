/// The frozen capability registry of `features.md`.
///
/// A capability id designates an exact and frozen set of operations, fields,
/// bounds and semantics. Ids are never renumbered and never reused. A bundle
/// declaring a single unknown id is refused with `incompatible_ruleset`: it
/// announces something this generator cannot honour, which is a version gap
/// rather than a forged file.
package enum Capability {
    package static let coreGraphV1: UInt32 = 1
    package static let asciiAndWhitespaceV1: UInt32 = 2
    package static let canonicalizationBasicV1: UInt32 = 3
    package static let canonicalizationConditionalV1: UInt32 = 4
    package static let identifierDispatchV1: UInt32 = 5
    package static let stringViewsV1: UInt32 = 10
    package static let capturesAndCallsV1: UInt32 = 11
    package static let formatAssertionsV1: UInt32 = 20
    package static let profilesV1: UInt32 = 21
    package static let checksumTristateV1: UInt32 = 30
    package static let checksumLuhnV1: UInt32 = 31
    package static let checksumMod97V1: UInt32 = 32
    package static let checksumWeightedV1: UInt32 = 33
    package static let checksumCompareConstantV1: UInt32 = 34
    package static let checksumIntegerPredicateV1: UInt32 = 35
    package static let provenanceV1: UInt32 = 40
    package static let provenanceTierV1: UInt32 = 41
    package static let checksumCustomAlphabetV1: UInt32 = 42

    /// Every capability this generator implements, in ascending order.
    package static let known: Set<UInt32> = [
        coreGraphV1,
        asciiAndWhitespaceV1,
        canonicalizationBasicV1,
        canonicalizationConditionalV1,
        identifierDispatchV1,
        stringViewsV1,
        capturesAndCallsV1,
        formatAssertionsV1,
        profilesV1,
        checksumTristateV1,
        checksumLuhnV1,
        checksumMod97V1,
        checksumWeightedV1,
        checksumCompareConstantV1,
        checksumIntegerPredicateV1,
        provenanceV1,
        provenanceTierV1,
        checksumCustomAlphabetV1,
    ]

    /// Human readable name of a known capability, used in generator reports.
    package static func name(of identifier: UInt32) -> String {
        switch identifier {
        case coreGraphV1: "CORE_GRAPH_V1"
        case asciiAndWhitespaceV1: "ASCII_AND_WHITESPACE_V1"
        case canonicalizationBasicV1: "CANONICALIZATION_BASIC_V1"
        case canonicalizationConditionalV1: "CANONICALIZATION_CONDITIONAL_V1"
        case identifierDispatchV1: "IDENTIFIER_DISPATCH_V1"
        case stringViewsV1: "STRING_VIEWS_V1"
        case capturesAndCallsV1: "CAPTURES_AND_CALLS_V1"
        case formatAssertionsV1: "FORMAT_ASSERTIONS_V1"
        case profilesV1: "PROFILES_V1"
        case checksumTristateV1: "CHECKSUM_TRISTATE_V1"
        case checksumLuhnV1: "CHECKSUM_LUHN_V1"
        case checksumMod97V1: "CHECKSUM_MOD97_V1"
        case checksumWeightedV1: "CHECKSUM_WEIGHTED_V1"
        case checksumCompareConstantV1: "CHECKSUM_COMPARE_CONSTANT_V1"
        case checksumIntegerPredicateV1: "CHECKSUM_INTEGER_PREDICATE_V1"
        case provenanceV1: "PROVENANCE_V1"
        case provenanceTierV1: "PROVENANCE_TIER_V1"
        case checksumCustomAlphabetV1: "CHECKSUM_CUSTOM_ALPHABET_V1"
        default: "UNKNOWN(\(identifier))"
        }
    }
}
