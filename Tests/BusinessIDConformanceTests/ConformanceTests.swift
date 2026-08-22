import Foundation
import Testing

@testable import BusinessIDConformance

package import BusinessIDWire

/// The shared corpus, run in full.
///
/// A partial run, a skipped category or a case declared not applicable is not
/// conformance. The corpus is executed as it ships; nothing here rewrites an
/// expectation in Swift.
@Suite("Conformance")
struct ConformanceTests {
    static func corpusPath() -> String {
        if let override = ProcessInfo.processInfo.environment["BUSINESSID_SPEC_ROOT"] {
            return override + "/spec/businessid-conformance.binpb"
        }
        return
            URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "spec/businessid-conformance.binpb")
            .path
    }

    @Test("The whole corpus passes")
    func wholeCorpus() throws {
        let runner = try ConformanceRunner(corpusPath: Self.corpusPath())
        #expect(runner.corpus.rulesVersion == "2026.08.17")
        #expect(runner.corpus.cases.count == 665)

        let outcome = try runner.run()
        for divergence in outcome.divergences.prefix(20) {
            Issue.record(Comment(rawValue: divergence.summary))
        }
        #expect(outcome.executed == 665)
        #expect(outcome.divergences.isEmpty)
    }

    @Test("Every operation of the corpus is exercised")
    func everyOperation() throws {
        let runner = try ConformanceRunner(corpusPath: Self.corpusPath())
        var counts: [Libbusinessid_Conformance_V1_Operation: Int] = [:]
        for testCase in runner.corpus.cases { counts[testCase.operation, default: 0] += 1 }
        #expect(counts[.canonicalize] == 13)
        #expect(counts[.validate] == 614)
        #expect(counts[.validateFormat] == 3)
        #expect(counts[.validateChecksum] == 1)
        #expect(counts[.loadRuleset] == 34)
    }

    /// A runner that reported no divergence because it compared nothing would
    /// look exactly like a conformant engine. These cases change one field of
    /// one response and require the runner to say so.
    @Suite("The runner reports a divergence on a single field")
    struct DivergenceDetection {
        private func runMutated(
            _ mutate: @escaping (inout Libbusinessid_Testee_V1_TesteeResponse) -> Void
        ) throws -> [ConformanceRunner.Divergence] {
            let runner = try ConformanceRunner(corpusPath: ConformanceTests.corpusPath())
            return try runner.run { request in
                var response = TesteeCoreShim.respond(to: request)
                mutate(&response)
                return response
            }.divergences
        }

        @Test("A changed canonical value is reported")
        func canonicalValue() throws {
            let divergences = try runMutated { response in
                guard case .validationReport(var report) = response.result else { return }
                report.canonicalValue += "X"
                response.result = .validationReport(report)
            }
            #expect(divergences.contains { $0.field == "canonical_value" })
        }

        @Test("A changed message key is reported")
        func messageKey() throws {
            let divergences = try runMutated { response in
                guard case .validationReport(var report) = response.result else { return }
                report.format.messageKey = "not.the.declared.key"
                response.result = .validationReport(report)
            }
            #expect(divergences.contains { $0.field == "format.message_key" })
        }

        @Test("A dropped country code is reported")
        func countryCode() throws {
            let divergences = try runMutated { response in
                guard case .validationReport(var report) = response.result else { return }
                report.clearCountryCode()
                response.result = .validationReport(report)
            }
            #expect(divergences.contains { $0.field == "country_code" })
        }

        @Test("A changed checksum status is reported")
        func checksumStatus() throws {
            let divergences = try runMutated { response in
                guard case .validationReport(var report) = response.result else { return }
                report.checksum.status = .valid
                response.result = .validationReport(report)
            }
            #expect(divergences.contains { $0.field == "checksum.status" })
        }

        @Test("A hostile bundle reported as accepted is reported")
        func acceptedHostileBundle() throws {
            let divergences = try runMutated { response in
                guard case .load(var load) = response.result else { return }
                load.accepted = true
                load.engineError = ""
                response.result = .load(load)
            }
            #expect(divergences.contains { $0.field == "accepted" })
        }

        @Test("A desynchronized exchange is reported rather than silently scored")
        func desynchronized() throws {
            let divergences = try runMutated { response in response.caseID = "another-case" }
            #expect(divergences.allSatisfy { $0.field == "case_id" })
            #expect(divergences.count == 665)
        }
    }
}
