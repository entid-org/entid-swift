/// Which variants of a format a validation accepts.
///
/// The inclusion criterion for a variant is use, never issuance date: a value
/// conforming to a variant that is no longer issued still appears on an old
/// invoice, and a system processing that invoice must keep accepting it. The
/// profile is the only normative mechanism separating such a historical variant
/// from a current one.
public enum ValidationProfile: String, Sendable, Hashable, Codable, CaseIterable {
    /// Accepts current variants and the documented historical ones that can
    /// still legitimately appear. The normative default.
    case compatible

    /// Opt-in. Accepts only the currently issued variants a rule declares
    /// explicitly. It never changes the canonicalization the two profiles share.
    case strictCurrent = "strict_current"
}

/// Options of a validation.
///
/// The absence of a profile is meaningful and is not the same as asking for
/// `compatible`: it is what lets the selected definition apply its own
/// `default_profile`. An API that filled the field in by default would make
/// that default unreachable, because the engine could no longer tell a silent
/// caller from one asking for `compatible`.
public struct ValidationOptions: Sendable, Hashable {
    /// Which variants to accept, or `nil` to let the selected definition
    /// apply its own default.
    public var profile: ValidationProfile?

    /// Creates options. Leaving `profile` at `nil` is not the same as asking
    /// for ``ValidationProfile/compatible``: it is what lets a definition's own
    /// default apply.
    public init(profile: ValidationProfile? = nil) {
        self.profile = profile
    }
}
