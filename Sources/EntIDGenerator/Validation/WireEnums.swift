internal import EntIDWire

/// Recognising a decoded enum value, explicitly.
///
/// `ir.md` check 2 keeps decoding at the wire level: an unrecognised enum
/// value survives the decode and travels to the check that owns its field.
/// These initialisers are that check. `UNSPECIFIED` is refused like every
/// other zero enum value, and an unrecognised number is refused as
/// `invalid_ruleset` rather than silently defaulted.
extension ValueType {
    init?(wire: Libbusinessid_Ir_V1_ValueType) {
        switch wire {
        case .string: self = .string
        case .integer: self = .integer
        case .boolean: self = .boolean
        case .canonicalizationStep: self = .canonicalizationStep
        case .assertion: self = .assertion
        case .checksumOutcome: self = .checksumOutcome
        case .unspecified, .UNRECOGNIZED: return nil
        }
    }
}

extension ProgramKind {
    init?(wire: Libbusinessid_Ir_V1_ProgramKind) {
        switch wire {
        case .canonicalization: self = .canonicalization
        case .format: self = .format
        case .checksum: self = .checksum
        case .unspecified, .UNRECOGNIZED: return nil
        }
    }
}

extension WeightAlignment {
    init?(wire: Libbusinessid_Ir_V1_WeightAlignment) {
        switch wire {
        case .left: self = .left
        case .right: self = .right
        case .cycle: self = .cycle
        case .unspecified, .UNRECOGNIZED: return nil
        }
    }
}

extension CharMapping {
    init?(wire: Libbusinessid_Ir_V1_CharMapping) {
        switch wire {
        case .digitValue: self = .digitValue
        case .alnumBase36: self = .alnumBase36
        case .customAlphabet: self = .customAlphabet
        case .unspecified, .UNRECOGNIZED: return nil
        }
    }
}

extension SourceTier {
    /// `PROVENANCE_TIER_V1`: `tier` is not `optional` in the schema, so an
    /// omitted field and `SOURCE_TIER_UNSPECIFIED` are the same bytes.
    /// `UNSPECIFIED` therefore means the source states no tier, and only a
    /// stated tier requires the capability. A value outside the enumeration
    /// stays `invalid_ruleset`, which is what `nil` from a non `.unspecified`
    /// input reports.
    /// `.stated(nil)` means the source states no tier; `nil` means the value
    /// lies outside the enumeration, which stays `invalid_ruleset`.
    static func recognised(wire: Libbusinessid_Ir_V1_SourceTier) -> Stated? {
        switch wire {
        case .unspecified: Stated(tier: nil)
        case .primary: Stated(tier: .primary)
        case .secondary: Stated(tier: .secondary)
        case .UNRECOGNIZED: nil
        }
    }

    struct Stated: Sendable, Hashable {
        let tier: SourceTier?
    }
}

extension ReasonCode {
    init?(wire: Libbusinessid_Ir_V1_ReasonCode) {
        switch wire {
        case .ok: self = .ok
        case .empty: self = .empty
        case .invalidLength: self = .invalidLength
        case .invalidCharacters: self = .invalidCharacters
        case .invalidFormat: self = .invalidFormat
        case .invalidChecksum: self = .invalidChecksum
        case .missingCountryCode: self = .missingCountryCode
        case .countryMismatch: self = .countryMismatch
        case .unsupportedKind: self = .unsupportedKind
        case .unsupportedCountry: self = .unsupportedCountry
        case .unsupportedFormat: self = .unsupportedFormat
        case .unsupportedChecksum: self = .unsupportedChecksum
        case .checksumNotPublished: self = .checksumNotPublished
        case .notRequested: self = .notRequested
        case .notRunFormatInvalid: self = .notRunFormatInvalid
        case .notRunFormatUnsupported: self = .notRunFormatUnsupported
        case .registryNotConfigured: self = .registryNotConfigured
        case .incompatibleRuleset: self = .incompatibleRuleset
        case .invalidRuleset: self = .invalidRuleset
        case .inputTooLong: self = .inputTooLong
        case .invalidEncoding: self = .invalidEncoding
        case .unspecified, .UNRECOGNIZED: return nil
        }
    }
}
