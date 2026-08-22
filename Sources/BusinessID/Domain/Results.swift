/// The outcome of one validation step.
public enum StepStatus: String, Sendable, Hashable, Codable, CaseIterable {
    /// Every applicable rule of the step succeeded.
    case valid
    /// An applicable rule proves the failure.
    case invalid
    /// No conclusion is possible with this ruleset. Never a proof of anything.
    case unsupported
    /// An earlier step forbids or makes this one pointless.
    case notRun = "not_run"
}

/// The step a result belongs to.
public enum ValidationLevel: String, Sendable, Hashable, Codable, CaseIterable {
    case format
    case checksum
    /// Reserved. Registry lookup is not part of this version, and no local
    /// validation ever produces this level.
    case registry
}

/// The immutable V1 registry of machine readable reasons.
///
/// Engines may add a technical error type but never invent a business reason
/// code: the registry evolves in the specification repository or not at all.
public enum ReasonCode: String, Sendable, Hashable, Codable, CaseIterable {
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
    /// Reserved for the deferred registry level. Unreachable in this version.
    case registryNotConfigured = "registry_not_configured"
    case incompatibleRuleset = "incompatible_ruleset"
    case invalidRuleset = "invalid_ruleset"
    case inputTooLong = "input_too_long"
    case invalidEncoding = "invalid_encoding"
}

/// One validation level as the engine resolved it.
public struct StepResult: Sendable, Hashable, Codable {
    public let level: ValidationLevel
    public let status: StepStatus
    public let reasonCode: ReasonCode
    /// The key the rule carries, for a localized message the engine does not
    /// itself provide.
    ///
    /// Absent whenever the result was produced before any rule assertion —
    /// dispatch, `inputTooLong`, `notRequested` and the `notRun` reasons. An
    /// assertion or a checksum declared by the ruleset keeps its key exactly,
    /// including when it declares none.
    public let messageKey: String?

    public init(
        level: ValidationLevel,
        status: StepStatus,
        reasonCode: ReasonCode,
        messageKey: String? = nil
    ) {
        self.level = level
        self.status = status
        self.reasonCode = reasonCode
        self.messageKey = messageKey
    }
}

/// The result of a validation.
///
/// There is deliberately no `isValid` on the whole report: a format that is
/// valid with a checksum that is unsupported is neither fully validated nor
/// invalid. The named properties below say which question they answer.
public struct ValidationReport: Sendable, Hashable, Codable {
    public let kind: IdentifierKind
    /// The raw string the caller supplied, unchanged.
    public let inputValue: String
    public let canonicalValue: String
    public let countryCode: String?
    public let profile: ValidationProfile
    public let rulesVersion: String
    public let formatVersion: Int
    public let engineVersion: String
    public let format: StepResult
    public let checksum: StepResult

    public init(
        kind: IdentifierKind,
        inputValue: String,
        canonicalValue: String,
        countryCode: String?,
        profile: ValidationProfile,
        rulesVersion: String,
        formatVersion: Int,
        engineVersion: String,
        format: StepResult,
        checksum: StepResult
    ) {
        self.kind = kind
        self.inputValue = inputValue
        self.canonicalValue = canonicalValue
        self.countryCode = countryCode
        self.profile = profile
        self.rulesVersion = rulesVersion
        self.formatVersion = formatVersion
        self.engineVersion = engineVersion
        self.format = format
        self.checksum = checksum
    }

    /// The shape is compatible with a documented variant.
    public var isFormatValid: Bool { format.status == .valid }

    /// The documented internal check is satisfied.
    public var isChecksumValid: Bool { checksum.status == .valid }

    /// Both steps concluded positively. This is still not a claim that the
    /// business exists: no registry was consulted.
    public var isFullyValidated: Bool { isFormatValid && isChecksumValid }

    /// At least one executed step proves an invalidity.
    public var isInvalid: Bool { format.status == .invalid || checksum.status == .invalid }
}

/// The result of a canonicalization.
///
/// `notRun` is never a final status here: canonicalization either produced a
/// value, proved a contradiction between an explicit country and a recognised
/// prefix, or could not conclude.
public struct CanonicalizationResult: Sendable, Hashable, Codable {
    public let kind: IdentifierKind
    public let inputValue: String
    public let canonicalValue: String
    public let countryCode: String?
    public let profile: ValidationProfile
    public let rulesVersion: String
    public let formatVersion: Int
    public let engineVersion: String
    public let status: StepStatus
    public let reasonCode: ReasonCode
    public let messageKey: String?

    public init(
        kind: IdentifierKind,
        inputValue: String,
        canonicalValue: String,
        countryCode: String?,
        profile: ValidationProfile,
        rulesVersion: String,
        formatVersion: Int,
        engineVersion: String,
        status: StepStatus,
        reasonCode: ReasonCode,
        messageKey: String? = nil
    ) {
        self.kind = kind
        self.inputValue = inputValue
        self.canonicalValue = canonicalValue
        self.countryCode = countryCode
        self.profile = profile
        self.rulesVersion = rulesVersion
        self.formatVersion = formatVersion
        self.engineVersion = engineVersion
        self.status = status
        self.reasonCode = reasonCode
        self.messageKey = messageKey
    }

    public var isSucceeded: Bool { status == .valid }
}

/// What a caller wants validated.
public struct IdentifierInput: Sendable, Hashable, Codable {
    public let kind: IdentifierKind
    /// Kept exactly as supplied. The engine never modifies it in place.
    public let value: String
    /// Optional context. When supplied, the ruleset's country canonicalization
    /// applies to it. A proved conflict between this and a recognised prefix
    /// produces `countryMismatch`.
    public let countryCode: String?

    public init(kind: IdentifierKind, value: String, countryCode: String? = nil) {
        self.kind = kind
        self.value = value
        self.countryCode = countryCode
    }
}
