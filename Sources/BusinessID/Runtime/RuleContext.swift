/// What a format or checksum program can read.
///
/// A rule reads nothing else: no clock, no environment, no locale, no network
/// and no random source.
struct RuleContext: Sendable {
    /// The canonical value of the identifier under validation, which is what
    /// `value()` yields even inside a called program.
    let value: [Unicode.Scalar]
    /// The canonical country code of the selected dispatch target, which
    /// `country_code()` yields. Absent for a GLOBAL target.
    ///
    /// This is not the country the report carries. A GLOBAL definition keeps a
    /// well formed country context in its result while `country_code()` yields
    /// the absent string in the same evaluation, because a GLOBAL target has no
    /// country of its own.
    let country: [Unicode.Scalar]?
    /// The effective profile, resolved before the definition's programs run.
    let profile: ValidationProfile
}

/// What a canonicalization program can read besides the current value.
struct CanonicalizationContext: Sendable {
    let profile: ValidationProfile
    /// The accepted prefixes of the selected dispatch target, read only by
    /// `prepend_country_if_missing`. Empty for a pre-canonicalization program,
    /// which the load checks forbid from using that step at all.
    let acceptedPrefixes: [[Unicode.Scalar]]
    /// The canonical prefix of the target, or its country code when it declares
    /// none.
    let canonicalPrefix: [Unicode.Scalar]

    static let dispatch = CanonicalizationContext(
        profile: .compatible, acceptedPrefixes: [], canonicalPrefix: []
    )

    init(
        profile: ValidationProfile,
        acceptedPrefixes: [[Unicode.Scalar]] = [],
        canonicalPrefix: [Unicode.Scalar] = []
    ) {
        self.profile = profile
        self.acceptedPrefixes = acceptedPrefixes
        self.canonicalPrefix = canonicalPrefix
    }
}
