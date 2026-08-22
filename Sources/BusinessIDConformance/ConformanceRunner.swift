internal import BusinessIDTestee
package import BusinessIDWire

internal import struct Foundation.Data
internal import class Foundation.FileManager

/// Reads the corpus, drives a testee and decides conformance.
///
/// This is the only place that reads an expected result. The testee never sees
/// one, so it cannot declare itself conformant by comparing too weakly or by
/// ignoring a field that happens to be absent.
///
/// The reference runner lives in the specification repository and is not
/// shipped with the artefacts under `spec/`. This one takes its place locally
/// so that the corpus can be run at all; it compares every field the testee
/// protocol transports, and nothing about it reaches the shipped library.
package struct ConformanceRunner {
    package let corpus: Libbusinessid_Conformance_V1_ConformanceBundle

    package init(corpus: Libbusinessid_Conformance_V1_ConformanceBundle) {
        self.corpus = corpus
    }

    package init(corpusPath: String) throws {
        guard let data = FileManager.default.contents(atPath: corpusPath) else {
            throw Failure.unreadableCorpus(corpusPath)
        }
        corpus = try Libbusinessid_Conformance_V1_ConformanceBundle(serializedBytes: [UInt8](data))
    }

    package enum Failure: Error, CustomStringConvertible {
        case unreadableCorpus(String)

        package var description: String {
            switch self {
            case .unreadableCorpus(let path): "cannot read the conformance corpus at \(path)"
            }
        }
    }

    /// One reported divergence.
    package struct Divergence: Sendable, Hashable {
        package let caseID: String
        package let description: String
        package let field: String
        package let expected: String
        package let observed: String

        package var summary: String {
            "\(caseID): \(field) expected \(expected), observed \(observed)\n    \(description)"
        }
    }

    package struct Outcome: Sendable {
        package let executed: Int
        package let divergences: [Divergence]
        package var isConformant: Bool { divergences.isEmpty }
    }

    /// Runs every case. A partial run, a skipped category or a case declared
    /// not applicable is not conformance.
    package func run(
        transport: (Libbusinessid_Testee_V1_TesteeRequest) throws -> Libbusinessid_Testee_V1_TesteeResponse =
            { TesteeCore.respond(to: $0) }
    ) rethrows -> Outcome {
        var divergences: [Divergence] = []
        for testCase in corpus.cases {
            let response = try transport(request(for: testCase))
            divergences.append(contentsOf: compare(testCase, response))
        }
        return Outcome(executed: corpus.cases.count, divergences: divergences)
    }

    package func request(
        for testCase: Libbusinessid_Conformance_V1_ConformanceCase
    ) -> Libbusinessid_Testee_V1_TesteeRequest {
        var request = Libbusinessid_Testee_V1_TesteeRequest()
        request.caseID = testCase.id
        request.operation = testCase.operation
        request.input = testCase.input
        request.kind = testCase.kind
        if testCase.hasCountryCode { request.countryCode = testCase.countryCode }
        // A case that states no profile leaves the field absent, which is what
        // lets a definition's default apply.
        if !testCase.profile.isEmpty { request.profile = testCase.profile }
        if testCase.hasRulesPayload { request.rulesPayload = testCase.rulesPayload }
        return request
    }

    // MARK: - Comparison

    private func compare(
        _ testCase: Libbusinessid_Conformance_V1_ConformanceCase,
        _ response: Libbusinessid_Testee_V1_TesteeResponse
    ) -> [Divergence] {
        var found: [Divergence] = []
        func check(_ field: String, _ expected: String, _ observed: String) {
            guard expected != observed else { return }
            found.append(
                Divergence(
                    caseID: testCase.id,
                    description: testCase.description_p,
                    field: field,
                    expected: expected,
                    observed: observed
                )
            )
        }

        guard response.caseID == testCase.id else {
            check("case_id", testCase.id, response.caseID)
            return found
        }

        switch (testCase.operation, response.result) {
        case (.loadRuleset, .load(let load)):
            check("accepted", "false", String(load.accepted))
            check("engine_error", testCase.expectedEngineError, load.engineError)

        case (.canonicalize, .canonicalization(let observed)):
            guard case .canonicalization(let expected)? = testCase.expected.value else {
                check("expected", "canonicalization", "another shape")
                break
            }
            check("kind", expected.kind, observed.kind)
            check("canonical_value", expected.canonicalValue, observed.canonicalValue)
            check(
                "country_code",
                expected.hasCountryCode ? expected.countryCode : "<absent>",
                observed.hasCountryCode ? observed.countryCode : "<absent>"
            )
            check("status", name(expected.status), name(observed.status))
            check("reason_code", name(expected.reasonCode), name(observed.reasonCode))

        case (.validate, .validationReport(let observed)),
            (.validateFormat, .validationReport(let observed)),
            (.validateChecksum, .validationReport(let observed)):
            guard case .validationReport(let expected)? = testCase.expected.value else {
                check("expected", "validation_report", "another shape")
                break
            }
            check("kind", expected.kind, observed.kind)
            check("canonical_value", expected.canonicalValue, observed.canonicalValue)
            check(
                "country_code",
                expected.hasCountryCode ? expected.countryCode : "<absent>",
                observed.hasCountryCode ? observed.countryCode : "<absent>"
            )
            compareStep("format", expected.format, observed.format, check)
            compareStep("checksum", expected.checksum, observed.checksum, check)

        case (_, .failure(let failure)):
            check("result", "an observation", "failure \(failure.kind): \(failure.detail)")

        default:
            check("result", "an observation of the requested shape", "another shape")
        }
        return found
    }

    private func compareStep(
        _ level: String,
        _ expected: Libbusinessid_Conformance_V1_ExpectedStep,
        _ observed: Libbusinessid_Testee_V1_ObservedStep,
        _ check: (String, String, String) -> Void
    ) {
        check("\(level).status", name(expected.status), name(observed.status))
        check("\(level).reason_code", name(expected.reasonCode), name(observed.reasonCode))
        // The key is compared whenever the corpus states one. Without this
        // field the tests compared only the code, and an engine could emit any
        // key at all without a case noticing.
        check(
            "\(level).message_key",
            expected.hasMessageKey ? expected.messageKey : "<absent>",
            observed.hasMessageKey ? observed.messageKey : "<absent>"
        )
    }

    private func name(_ status: Libbusinessid_Conformance_V1_StepStatus) -> String {
        switch status {
        case .valid: "valid"
        case .invalid: "invalid"
        case .unsupported: "unsupported"
        case .notRun: "not_run"
        case .unspecified: "unspecified"
        case .UNRECOGNIZED(let value): "unrecognised(\(value))"
        }
    }

    private func name(_ reason: Libbusinessid_Ir_V1_ReasonCode) -> String {
        switch reason {
        case .ok: "ok"
        case .empty: "empty"
        case .invalidLength: "invalid_length"
        case .invalidCharacters: "invalid_characters"
        case .invalidFormat: "invalid_format"
        case .invalidChecksum: "invalid_checksum"
        case .missingCountryCode: "missing_country_code"
        case .countryMismatch: "country_mismatch"
        case .unsupportedKind: "unsupported_kind"
        case .unsupportedCountry: "unsupported_country"
        case .unsupportedFormat: "unsupported_format"
        case .unsupportedChecksum: "unsupported_checksum"
        case .checksumNotPublished: "checksum_not_published"
        case .notRequested: "not_requested"
        case .notRunFormatInvalid: "not_run_format_invalid"
        case .notRunFormatUnsupported: "not_run_format_unsupported"
        case .registryNotConfigured: "registry_not_configured"
        case .incompatibleRuleset: "incompatible_ruleset"
        case .invalidRuleset: "invalid_ruleset"
        case .inputTooLong: "input_too_long"
        case .invalidEncoding: "invalid_encoding"
        case .unspecified: "unspecified"
        case .UNRECOGNIZED(let value): "unrecognised(\(value))"
        }
    }
}
