internal import EntID
internal import EntIDGenerator
package import EntIDWire

internal import struct Foundation.Data

/// Translates one conformance request into one call of the public API, and the
/// result back into a response.
///
/// It never reads the corpus, never sees an expected result and never adapts to
/// the case it receives. That is what makes the absence of cheating something a
/// reader can verify rather than something this package asserts: the code below
/// is the whole of it.
package enum TesteeCore {
    package static func respond(
        to request: Libbusinessid_Testee_V1_TesteeRequest
    ) -> Libbusinessid_Testee_V1_TesteeResponse {
        var response = Libbusinessid_Testee_V1_TesteeResponse()
        // The identifier is echoed so that a desynchronized exchange is
        // detected rather than silently scoring the wrong case. It is used for
        // nothing else.
        response.caseID = request.caseID

        switch request.operation {
        case .canonicalize, .validate, .validateFormat, .validateChecksum:
            guard let options = options(for: request) else {
                response.result = .failure(
                    failure(.internalError, "profile \(request.profile) is not a V1 profile")
                )
                return response
            }
            let input = IdentifierInput(
                kind: IdentifierKind(request.kind),
                value: request.input,
                countryCode: request.hasCountryCode ? request.countryCode : nil
            )
            let engine = EntIDEngine.default
            switch request.operation {
            case .canonicalize:
                response.result = .canonicalization(
                    observed(engine.canonicalize(input, options: options))
                )
            case .validate:
                response.result = .validationReport(observed(engine.validate(input, options: options)))
            case .validateFormat:
                response.result = .validationReport(
                    observed(engine.validateFormat(input, options: options))
                )
            default:
                response.result = .validationReport(
                    observed(engine.validateChecksum(input, options: options))
                )
            }

        case .loadRuleset:
            // These address the generator, not the engine: a generated engine
            // loads no bundle. A truncated bundle or one carrying a call cycle
            // must make generation fail.
            var load = Libbusinessid_Testee_V1_ObservedLoad()
            do {
                _ = try RuleBundleLoader.load([UInt8](request.rulesPayload))
                load.accepted = true
            } catch {
                load.accepted = false
                load.engineError = error.engineErrorName
            }
            response.result = .load(load)

        case .unspecified, .UNRECOGNIZED:
            response.result = .failure(failure(.unsupportedOperation, "unspecified operation"))
        }
        return response
    }

    // MARK: - Request

    /// The absence of a profile is meaningful and is what lets a definition's
    /// `default_profile` apply, so it is never conflated with a profile named
    /// the empty string.
    private static func options(
        for request: Libbusinessid_Testee_V1_TesteeRequest
    ) -> ValidationOptions? {
        guard request.hasProfile else { return ValidationOptions() }
        guard let profile = ValidationProfile(rawValue: request.profile) else { return nil }
        return ValidationOptions(profile: profile)
    }

    // MARK: - Response

    private static func observed(
        _ result: CanonicalizationResult
    ) -> Libbusinessid_Testee_V1_ObservedCanonicalization {
        var observed = Libbusinessid_Testee_V1_ObservedCanonicalization()
        observed.kind = result.kind.rawValue
        observed.canonicalValue = result.canonicalValue
        if let country = result.countryCode { observed.countryCode = country }
        observed.status = wire(result.status)
        observed.reasonCode = wire(result.reasonCode)
        return observed
    }

    private static func observed(
        _ report: ValidationReport
    ) -> Libbusinessid_Testee_V1_ObservedValidationReport {
        var observed = Libbusinessid_Testee_V1_ObservedValidationReport()
        observed.kind = report.kind.rawValue
        observed.canonicalValue = report.canonicalValue
        if let country = report.countryCode { observed.countryCode = country }
        observed.format = step(report.format)
        observed.checksum = step(report.checksum)
        return observed
    }

    private static func step(_ result: EntID.StepResult) -> Libbusinessid_Testee_V1_ObservedStep {
        var observed = Libbusinessid_Testee_V1_ObservedStep()
        observed.status = wire(result.status)
        observed.reasonCode = wire(result.reasonCode)
        // Absent when the result was produced before any rule assertion.
        if let key = result.messageKey { observed.messageKey = key }
        return observed
    }

    private static func failure(
        _ kind: Libbusinessid_Testee_V1_FailureKind,
        _ detail: String
    ) -> Libbusinessid_Testee_V1_TesteeFailure {
        var failure = Libbusinessid_Testee_V1_TesteeFailure()
        failure.kind = kind
        failure.detail = detail
        return failure
    }

    private static func wire(_ status: EntID.StepStatus) -> Libbusinessid_Conformance_V1_StepStatus {
        switch status {
        case .valid: .valid
        case .invalid: .invalid
        case .unsupported: .unsupported
        case .notRun: .notRun
        }
    }

    private static func wire(_ reason: EntID.ReasonCode) -> Libbusinessid_Ir_V1_ReasonCode {
        switch reason {
        case .ok: .ok
        case .empty: .empty
        case .invalidLength: .invalidLength
        case .invalidCharacters: .invalidCharacters
        case .invalidFormat: .invalidFormat
        case .invalidChecksum: .invalidChecksum
        case .missingCountryCode: .missingCountryCode
        case .countryMismatch: .countryMismatch
        case .unsupportedKind: .unsupportedKind
        case .unsupportedCountry: .unsupportedCountry
        case .unsupportedFormat: .unsupportedFormat
        case .unsupportedChecksum: .unsupportedChecksum
        case .checksumNotPublished: .checksumNotPublished
        case .notRequested: .notRequested
        case .notRunFormatInvalid: .notRunFormatInvalid
        case .notRunFormatUnsupported: .notRunFormatUnsupported
        case .registryNotConfigured: .registryNotConfigured
        case .incompatibleRuleset: .incompatibleRuleset
        case .invalidRuleset: .invalidRuleset
        case .inputTooLong: .inputTooLong
        case .invalidEncoding: .invalidEncoding
        }
    }
}
