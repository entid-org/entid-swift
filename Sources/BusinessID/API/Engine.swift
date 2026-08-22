/// The offline validation engine.
///
/// The engine holds no state. It is a value with no stored property, so sharing
/// it across tasks needs no lock and no `@unchecked` escape hatch: there is
/// nothing to protect. Every rule it applies was compiled into this package at
/// build time, so a validation performs no I/O, allocates nothing global and
/// consults nothing outside its arguments.
///
/// ## What it answers, and what it does not
///
/// A valid format means the shape is compatible with a documented variant. A
/// valid checksum means the documented internal check is satisfied. Neither is
/// a claim that a business exists, is active, or belongs to anyone: no registry
/// is consulted, here or anywhere in this version.
///
/// ## Not knowing is a result
///
/// Where no documented rule applies, the answer is `unsupported`, never
/// `invalid`. Refusing a valid identifier is the most serious defect this
/// project recognises, and turning an absence of knowledge into a rejection is
/// how it happens.
public struct BusinessIDEngine: Sendable {
    /// The ready to use engine. Creating another is equally cheap; this one
    /// exists so callers need not thread one through their own types.
    public static let `default` = BusinessIDEngine()

    public init() {}

    // MARK: - Versions and capabilities

    /// Business version of the rules, `YYYY.MM.PATCH`.
    public var rulesVersion: String { GeneratedRuleset.rulesVersion }

    /// Structural version of the IR the rules were compiled from.
    public var formatVersion: Int { GeneratedRuleset.formatVersion }

    /// Version of this package, independent of the two above.
    public var engineVersion: String { BusinessID.engineVersion }

    /// What this engine and its rules cover.
    public func rulesInfo() -> RulesInfo {
        RulesInfo(
            rulesVersion: GeneratedRuleset.rulesVersion,
            formatVersion: GeneratedRuleset.formatVersion,
            engineVersion: BusinessID.engineVersion,
            identifierCount: GeneratedRuleset.identifierCount,
            countryCount: GeneratedRuleset.countryCount,
            kinds: GeneratedRuleset.canonicalKinds
        )
    }

    /// The frozen capability ids the compiled rules require.
    public func capabilities() -> [Int] { GeneratedRuleset.capabilities }

    // MARK: - Operations

    /// Canonicalizes without validating.
    ///
    /// Runs the input bound, dispatch, pre-canonicalization and the definition's
    /// canonicalization, each phase at most once, and neither format nor
    /// checksum.
    public func canonicalize(
        _ input: IdentifierInput,
        options: ValidationOptions = .init()
    ) -> CanonicalizationResult {
        let resolution = resolve(input, options: options)
        switch resolution {
        case .failed(let failure):
            return CanonicalizationResult(
                kind: IdentifierKind(failure.kind),
                inputValue: input.value,
                canonicalValue: failure.canonicalValue,
                countryCode: failure.countryCode,
                profile: failure.profile,
                rulesVersion: GeneratedRuleset.rulesVersion,
                formatVersion: GeneratedRuleset.formatVersion,
                engineVersion: BusinessID.engineVersion,
                status: failure.status,
                reasonCode: failure.reasonCode
            )
        case .selected(let selected):
            return CanonicalizationResult(
                kind: IdentifierKind(selected.kind),
                inputValue: input.value,
                canonicalValue: String(String.UnicodeScalarView(selected.canonicalValue)),
                countryCode: selected.reportedCountry,
                profile: selected.profile,
                rulesVersion: GeneratedRuleset.rulesVersion,
                formatVersion: GeneratedRuleset.formatVersion,
                engineVersion: BusinessID.engineVersion,
                status: .valid,
                reasonCode: .ok
            )
        }
    }

    /// Validates format then checksum.
    public func validate(
        _ input: IdentifierInput,
        options: ValidationOptions = .init()
    ) -> ValidationReport {
        report(for: input, options: options, runChecksum: true)
    }

    /// Validates the format only, and reports the checksum as `notRun` with
    /// `notRequested`.
    ///
    /// It returns a whole report rather than an isolated step: a caller can
    /// then read both levels without having to remember which operation
    /// produced the value.
    public func validateFormat(
        _ input: IdentifierInput,
        options: ValidationOptions = .init()
    ) -> ValidationReport {
        report(for: input, options: options, runChecksum: false)
    }

    /// Validates the checksum, using the format as a mandatory guard.
    ///
    /// This returns exactly what ``validate(_:options:)`` returns for the same
    /// input and options. The separate operation exists to make a call site
    /// read clearly, never to skip the format: a checksum is never run on a
    /// value whose format was not validated.
    public func validateChecksum(
        _ input: IdentifierInput,
        options: ValidationOptions = .init()
    ) -> ValidationReport {
        report(for: input, options: options, runChecksum: true)
    }
}
