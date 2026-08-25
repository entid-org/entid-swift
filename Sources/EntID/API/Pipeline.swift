/// The normative pipeline: the input bound, the ten dispatch steps, then format
/// and checksum.
extension EntIDEngine {
    /// What dispatch produced.
    enum Resolution {
        case selected(Selected)
        case failed(Failure)
    }

    /// A definition was selected and both canonicalization phases ran.
    struct Selected {
        let kind: String
        let canonicalValue: [Unicode.Scalar]
        /// The country the result carries, which a GLOBAL target keeps from the
        /// caller's context while `country_code()` stays absent.
        let reportedCountry: String?
        /// The country of the selected target, absent for a GLOBAL target.
        let targetCountry: String?
        let profile: ValidationProfile
        let definition: Int
    }

    /// Dispatch stopped before selecting a definition.
    struct Failure {
        let kind: String
        let canonicalValue: String
        let countryCode: String?
        let profile: ValidationProfile
        let status: StepStatus
        let reasonCode: ReasonCode
    }

    // MARK: - Dispatch

    func resolve(_ input: IdentifierInput, options: ValidationOptions) -> Resolution {
        // Dispatch runs under the caller's profile, or `compatible` when the
        // caller gives none. A definition cannot supply its own default before
        // it has been selected.
        let dispatchProfile = options.profile ?? .compatible
        let requestedKind = Self.normalizedKindToken(input.kind.rawValue)

        // The user input bound is an obligation of the engine: a longer input
        // is refused without being processed. A safety bound is not by itself a
        // business proof of invalidity, so it reports `unsupported`.
        guard input.value.utf8.count <= inputByteLimit else {
            return .failed(
                Failure(
                    kind: requestedKind,
                    canonicalValue: input.value,
                    countryCode: input.countryCode,
                    profile: dispatchProfile,
                    status: .unsupported,
                    reasonCode: .inputTooLong
                )
            )
        }

        // Steps 2 and 3. A kind token that is malformed, or well formed and
        // unknown, is `unsupported_kind`, and no program runs.
        guard let dispatcher = GeneratedRuleset.dispatcher(forKind: requestedKind) else {
            return .failed(
                Failure(
                    kind: requestedKind,
                    canonicalValue: input.value,
                    countryCode: input.countryCode,
                    profile: dispatchProfile,
                    status: .unsupported,
                    reasonCode: .unsupportedKind
                )
            )
        }
        let canonicalKind = GeneratedRuleset.canonicalKind(dispatcher)

        // Step 4. The pre-canonicalization program runs on the raw value as
        // soon as the dispatcher is resolved, before any country decision, so a
        // result that stops at step 5 still carries the pre-canonical value.
        var value = Array(input.value.unicodeScalars)
        GeneratedRuleset.preCanonicalize(dispatcher, &value, dispatchProfile)
        let preCanonical = String(String.UnicodeScalarView(value))

        func failed(_ status: StepStatus, _ reason: ReasonCode, country: String?) -> Resolution {
            .failed(
                Failure(
                    kind: canonicalKind,
                    canonicalValue: preCanonical,
                    countryCode: country,
                    profile: dispatchProfile,
                    status: status,
                    reasonCode: reason
                )
            )
        }

        // Step 5. An empty token behaves like an absent context.
        var normalizedCountry: String?
        var countryTarget: Int?
        if let raw = input.countryCode, !Self.trimmedASCII(raw).isEmpty {
            let token = Self.normalizedCountryToken(raw)
            guard TokenShape.isWellFormedCountry(token) else {
                return failed(.unsupported, .unsupportedCountry, country: raw)
            }
            let resolved = GeneratedRuleset.resolveCountryAlias(dispatcher, token)
            normalizedCountry = resolved
            countryTarget = GeneratedRuleset.countryTarget(dispatcher, resolved)
            if countryTarget == nil, GeneratedRuleset.isCountrySpecific(dispatcher) {
                return failed(.unsupported, .unsupportedCountry, country: resolved)
            }
        }

        // Step 6. The target owning the longest exactly matching prefix. The
        // load checks proved one prefix value belongs to at most one target, so
        // nothing here depends on the serialization order.
        let prefixTarget = GeneratedRuleset.prefixTarget(dispatcher, value)

        // Step 7.
        if let countryTarget, let prefixTarget, countryTarget != prefixTarget {
            return failed(.invalid, .countryMismatch, country: normalizedCountry)
        }

        // Steps 8 and 9.
        let target =
            countryTarget ?? prefixTarget ?? GeneratedRuleset.globalTarget(dispatcher)
            ?? GeneratedRuleset.unprefixedTarget(dispatcher)
        guard let target else {
            return failed(.unsupported, .missingCountryCode, country: normalizedCountry)
        }

        // Once a definition is selected, its default profile applies when, and
        // only when, the caller supplied none.
        let definition = GeneratedRuleset.definition(ofTarget: target)
        let profile = options.profile ?? GeneratedRuleset.defaultProfile(definition)

        // Step 10.
        GeneratedRuleset.canonicalize(target: target, &value, profile)

        let targetCountry = GeneratedRuleset.targetCountry(target)
        return .selected(
            Selected(
                kind: canonicalKind,
                canonicalValue: value,
                // The country of a country target is its ISO code, even when
                // its business prefix differs — country `GR` with the canonical
                // VAT prefix `EL`. A GLOBAL target has none and keeps the
                // normalized context instead.
                reportedCountry: targetCountry ?? normalizedCountry,
                targetCountry: targetCountry,
                profile: profile,
                definition: definition
            )
        )
    }

    // MARK: - Validation

    func report(
        for input: IdentifierInput,
        options: ValidationOptions,
        runChecksum: Bool
    ) -> ValidationReport {
        switch resolve(input, options: options) {
        case .failed(let failure):
            // A proved contradiction between an explicit country and a
            // recognised prefix is the one dispatch outcome that proves an
            // invalidity; every other one is an absence of knowledge.
            let notRun: ReasonCode =
                failure.status == .invalid ? .notRunFormatInvalid : .notRunFormatUnsupported
            return ValidationReport(
                kind: IdentifierKind(failure.kind),
                inputValue: input.value,
                canonicalValue: failure.canonicalValue,
                countryCode: failure.countryCode,
                profile: failure.profile,
                rulesVersion: GeneratedRuleset.rulesVersion,
                formatVersion: GeneratedRuleset.formatVersion,
                engineVersion: EntID.engineVersion,
                format: StepResult(
                    level: .format, status: failure.status, reasonCode: failure.reasonCode
                ),
                checksum: StepResult(level: .checksum, status: .notRun, reasonCode: notRun)
            )

        case .selected(let selected):
            let context = RuleContext(
                value: selected.canonicalValue,
                country: selected.targetCountry.map { Array($0.unicodeScalars) },
                profile: selected.profile
            )
            let format = GeneratedRuleset.format(selected.definition, context)

            let formatStep: StepResult
            let checksumStep: StepResult
            switch format {
            case .fail(let reason, let key):
                formatStep = StepResult(
                    level: .format, status: .invalid, reasonCode: reason, messageKey: key
                )
                checksumStep = StepResult(
                    level: .checksum, status: .notRun, reasonCode: .notRunFormatInvalid
                )
            case .pass:
                formatStep = StepResult(level: .format, status: .valid, reasonCode: .ok)
                if runChecksum {
                    checksumStep = Self.step(
                        for: GeneratedRuleset.checksum(selected.definition, context)
                    )
                } else {
                    checksumStep = StepResult(
                        level: .checksum, status: .notRun, reasonCode: .notRequested
                    )
                }
            }

            return ValidationReport(
                kind: IdentifierKind(selected.kind),
                inputValue: input.value,
                canonicalValue: String(String.UnicodeScalarView(selected.canonicalValue)),
                countryCode: selected.reportedCountry,
                profile: selected.profile,
                rulesVersion: GeneratedRuleset.rulesVersion,
                formatVersion: GeneratedRuleset.formatVersion,
                engineVersion: EntID.engineVersion,
                format: formatStep,
                checksum: checksumStep
            )
        }
    }

    private static func step(for outcome: ChecksumOutcome) -> StepResult {
        switch outcome {
        case .valid:
            StepResult(level: .checksum, status: .valid, reasonCode: .ok)
        case .invalid(let key):
            StepResult(level: .checksum, status: .invalid, reasonCode: .invalidChecksum, messageKey: key)
        case .unsupported(let reason, let key):
            StepResult(level: .checksum, status: .unsupported, reasonCode: reason, messageKey: key)
        case .notApplicable:
            // A `CHOOSE` where no branch applies reports `unsupported_checksum`;
            // the load checks make a bare `WHEN` unreachable here.
            StepResult(level: .checksum, status: .unsupported, reasonCode: .unsupportedChecksum)
        }
    }

    // MARK: - Token normalization

    /// The maximum raw input, in UTF-8 bytes. Deliberately small: it is what
    /// makes a fixed size implementation possible.
    var inputByteLimit: Int { 1024 }

    /// Trim ASCII removes only `U+0009..U+000D` and `U+0020`, at both ends.
    static func trimmedASCII(_ token: String) -> [Unicode.Scalar] {
        var scalars = Array(token.unicodeScalars)
        var start = 0
        var end = scalars.count
        while start < end, Whitespace.isASCIITrimmable(scalars[start]) { start += 1 }
        while end > start, Whitespace.isASCIITrimmable(scalars[end - 1]) { end -= 1 }
        scalars = Array(scalars[start..<end])
        return scalars
    }

    static func normalizedKindToken(_ token: String) -> String {
        var scalars = trimmedASCII(token)
        for index in scalars.indices where ASCIIClass.isUpperLetter(scalars[index]) {
            if let lower = Unicode.Scalar(scalars[index].value + 0x20) { scalars[index] = lower }
        }
        return String(String.UnicodeScalarView(scalars))
    }

    static func normalizedCountryToken(_ token: String) -> String {
        let scalars = trimmedASCII(token).map(ASCIIClass.uppercased)
        return String(String.UnicodeScalarView(scalars))
    }
}

/// The ASCII token shapes dispatch requires.
enum TokenShape {
    static func isWellFormedCountry(_ token: String) -> Bool {
        let scalars = Array(token.unicodeScalars)
        return scalars.count == 2 && scalars.allSatisfy(ASCIIClass.isUpperLetter)
    }
}
