// The testee is driven as a subprocess, which no simulator can do, so this
// whole target is compiled out anywhere but macOS rather than skipped at run
// time. A skipped test reads as a passing one in a summary; an absent one does
// not.
#if os(macOS)

package import EntIDWire
import Testing

import struct Foundation.Data

/// The testee's own edges: the requests the protocol allows but the corpus
/// never sends.
///
/// A testee that answered one of these with a plausible observation instead of
/// a failure would let a missing capability read as a wrong answer, which is
/// exactly the distinction `TesteeFailure` exists to keep.
@Suite("Testee")
struct TesteeTests {
    private func request(
        _ operation: Entid_Conformance_V1_Operation,
        configure: (inout Entid_Testee_V1_TesteeRequest) -> Void = { _ in }
    ) -> Entid_Testee_V1_TesteeRequest {
        var request = Entid_Testee_V1_TesteeRequest()
        request.caseID = "unit"
        request.operation = operation
        request.kind = "siren"
        request.input = "012345674"
        configure(&request)
        return request
    }

    @Test("An unspecified operation is a failure, not an observation")
    func unspecifiedOperation() {
        let response = TesteeCoreShim.respond(to: request(.unspecified))
        #expect(response.caseID == "unit")
        guard case .failure(let failure) = response.result else {
            Issue.record("an unspecified operation produced an observation")
            return
        }
        #expect(failure.kind == .unsupportedOperation)
    }

    @Test("An operation number outside the enumeration is a failure")
    func unrecognisedOperation() {
        let response = TesteeCoreShim.respond(to: request(.UNRECOGNIZED(99)))
        guard case .failure(let failure) = response.result else {
            Issue.record("an unknown operation produced an observation")
            return
        }
        #expect(failure.kind == .unsupportedOperation)
    }

    @Test("A profile the V1 registry does not name is an internal failure")
    func unknownProfile() {
        // Not a conformance answer: the protocol carries a profile the engine
        // cannot represent, which is a broken exchange rather than a verdict.
        let response = TesteeCoreShim.respond(to: request(.validate) { $0.profile = "lenient" })
        guard case .failure(let failure) = response.result else {
            Issue.record("an unknown profile produced an observation")
            return
        }
        #expect(failure.kind == .internalError)
        #expect(failure.detail.contains("lenient"))
    }

    @Test("An absent profile is not a profile named the empty string")
    func absentProfile() {
        // Section 5.2 makes the absence meaningful: it is what lets a
        // definition's default_profile apply.
        let silent = TesteeCoreShim.respond(to: request(.validate))
        let empty = TesteeCoreShim.respond(to: request(.validate) { $0.profile = "" })

        guard case .validationReport = silent.result else {
            Issue.record("an absent profile must still validate")
            return
        }
        guard case .failure = empty.result else {
            Issue.record("a profile named the empty string is not a V1 profile")
            return
        }
    }

    @Test("Each operation answers with the shape the protocol declares")
    func responseShapes() {
        for operation in [
            Entid_Conformance_V1_Operation.validate,
            .validateFormat,
            .validateChecksum,
        ] {
            guard case .validationReport = TesteeCoreShim.respond(to: request(operation)).result else {
                Issue.record(Comment(rawValue: "\(operation) did not answer with a report"))
                continue
            }
        }
        guard case .canonicalization = TesteeCoreShim.respond(to: request(.canonicalize)).result else {
            Issue.record("canonicalize did not answer with a canonicalization")
            return
        }
    }

    @Test("A country code the caller did not supply stays absent in the answer")
    func absentCountryStaysAbsent() {
        let response = TesteeCoreShim.respond(
            to: request(.canonicalize) {
                $0.kind = "lei"
                $0.input = "0000-0000-0000-0000-0098"
            }
        )
        guard case .canonicalization(let observed) = response.result else {
            Issue.record("expected a canonicalization")
            return
        }
        #expect(!observed.hasCountryCode)
        #expect(observed.canonicalValue == "00000000000000000098")
    }

    @Test("A load_ruleset request reaches the generator and refuses a hostile bundle")
    func loadRuleset() {
        var hostile = request(.loadRuleset)
        hostile.rulesPayload = Data([0xFF, 0xFF, 0xFF])
        guard case .load(let load) = TesteeCoreShim.respond(to: hostile).result else {
            Issue.record("expected a load observation")
            return
        }
        #expect(!load.accepted)
        #expect(load.engineError == "invalid_ruleset")
    }

}
#endif
