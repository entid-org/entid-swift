/// The IR enumerations, mirrored into generator owned types.
///
/// Mirroring is not ceremony. A decoded Protobuf enum carries an unrecognised
/// case, and the whole point of `ir.md` check 2 staying at the wire level is
/// that an unrecognised value travels as far as the check that owns its field
/// rather than failing the decode. These types exist on the other side of that
/// check: once a value is one of them, it has been recognised.

/// Static type of a node output.
package enum ValueType: String, Sendable, Hashable, CaseIterable {
    case string = "VALUE_TYPE_STRING"
    case integer = "VALUE_TYPE_INTEGER"
    case boolean = "VALUE_TYPE_BOOLEAN"
    case canonicalizationStep = "VALUE_TYPE_CANONICALIZATION_STEP"
    case assertion = "VALUE_TYPE_ASSERTION"
    case checksumOutcome = "VALUE_TYPE_CHECKSUM_OUTCOME"
}

/// Which operations a program may contain.
package enum ProgramKind: String, Sendable, Hashable, CaseIterable {
    case canonicalization = "PROGRAM_KIND_CANONICALIZATION"
    case format = "PROGRAM_KIND_FORMAT"
    case checksum = "PROGRAM_KIND_CHECKSUM"
}

/// The immutable V1 registry of machine readable reasons.
package enum ReasonCode: String, Sendable, Hashable, CaseIterable {
    case ok
    case empty
    case invalidLength = "invalid_length"
    case invalidCharacters = "invalid_characters"
    case invalidFormat = "invalid_format"
    case invalidChecksum = "invalid_checksum"
    case missingCountryCode = "missing_country_code"
    case countryMismatch = "country_mismatch"
    case unsupportedKind = "unsupported_kind"
    case unsupportedCountry = "unsupported_country"
    case unsupportedFormat = "unsupported_format"
    case unsupportedChecksum = "unsupported_checksum"
    case checksumNotPublished = "checksum_not_published"
    case notRequested = "not_requested"
    case notRunFormatInvalid = "not_run_format_invalid"
    case notRunFormatUnsupported = "not_run_format_unsupported"
    case registryNotConfigured = "registry_not_configured"
    case incompatibleRuleset = "incompatible_ruleset"
    case invalidRuleset = "invalid_ruleset"
    case inputTooLong = "input_too_long"
    case invalidEncoding = "invalid_encoding"

    /// `ir.md` section 4: the reason codes `REQUIRE` accepts, restricted to
    /// those that prove an invalidity.
    package static let provingInvalidity: Set<ReasonCode> = [
        .empty, .invalidLength, .invalidCharacters, .invalidFormat, .countryMismatch,
    ]

    /// `ir.md` section 4: the reason codes `CHECKSUM_OP_KIND_UNSUPPORTED` and
    /// `IdentifierDefinition.absent_checksum_reason` accept.
    package static let absentChecksum: Set<ReasonCode> = [.unsupportedChecksum, .checksumNotPublished]
}

/// How weights are paired with input code points.
package enum WeightAlignment: String, Sendable, Hashable, CaseIterable {
    case left = "WEIGHT_ALIGNMENT_LEFT"
    case right = "WEIGHT_ALIGNMENT_RIGHT"
    case cycle = "WEIGHT_ALIGNMENT_CYCLE"
}

/// How a code point becomes a numeric contribution.
package enum CharMapping: String, Sendable, Hashable, CaseIterable {
    case digitValue = "CHAR_MAPPING_DIGIT_VALUE"
    case alnumBase36 = "CHAR_MAPPING_ALNUM_BASE36"
    case customAlphabet = "CHAR_MAPPING_CUSTOM_ALPHABET"
}

/// How close a source sits to the authority that defines the format.
///
/// `tier` is not `optional` in the schema, so a `Source` that omits the field
/// and one that sets `SOURCE_TIER_UNSPECIFIED` are the same bytes. Absence here
/// therefore means the source states no tier, and only a stated tier requires
/// `PROVENANCE_TIER_V1`.
package enum SourceTier: String, Sendable, Hashable, CaseIterable {
    case primary = "SOURCE_TIER_PRIMARY"
    case secondary = "SOURCE_TIER_SECONDARY"
}
