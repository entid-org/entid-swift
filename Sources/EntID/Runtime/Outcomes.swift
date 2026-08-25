/// The result of a format program.
enum AssertionOutcome: Sendable, Equatable {
    case pass
    /// The first failing assertion, whose reason code and message key become
    /// the result of the program.
    case fail(ReasonCode, String?)
}

/// The tri-state result of a checksum program.
///
/// An indeterminate integer reaches `unsupported`, never `invalid`: refusing a
/// valid identifier is the most serious defect this project recognises.
enum ChecksumOutcome: Sendable, Equatable {
    case valid
    case invalid(String?)
    case unsupported(ReasonCode, String?)
    /// A `WHEN` branch whose predicate is false. It is only ever produced as a
    /// direct operand of `CHOOSE`, and the load checks refuse a ruleset where
    /// it could be observed anywhere else.
    case notApplicable

    static let unsupportedChecksum = ChecksumOutcome.unsupported(.unsupportedChecksum, nil)
}

/// An integer expression that may be indeterminate.
///
/// Indeterminate is `nil`. It propagates through every integer operation and
/// makes the enclosing checksum node `unsupported`.
typealias IntegerValue = Int64?
