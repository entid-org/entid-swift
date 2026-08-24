// The testee is driven as a subprocess, which no simulator can do, so this
// whole target is compiled out anywhere but macOS rather than skipped at run
// time. A skipped test reads as a passing one in a summary; an absent one does
// not.
#if os(macOS)

package import BusinessIDWire
import Foundation
import Testing

/// What the shared corpus carries in this release.
///
/// These are not proofs about the testee, and that is why they live outside
/// `TesteeHonestyTests`: `engine.md` section 11.3 requires the honesty suite to
/// invent its requests rather than open the corpus, so a suite that has to read
/// the corpus cannot be the same one.
///
/// The runner runs whatever the corpus holds, so a case disappearing between
/// two rules versions would pass silently. This is the tripwire for that.
@Suite("Corpus shape")
struct CorpusShapeTests {
    @Test("The corpus carries what this release says it carries")
    func corpusShape() throws {
        let corpus = try TesteeHarness.corpus()
        #expect(corpus.rulesVersion == BusinessIDRulesVersion.locked)
        #expect(corpus.cases.count == 673)

        var counts: [Libbusinessid_Conformance_V1_Operation: Int] = [:]
        for testCase in corpus.cases { counts[testCase.operation, default: 0] += 1 }
        #expect(counts[.canonicalize] == 13)
        #expect(counts[.validate] == 621)
        #expect(counts[.validateFormat] == 3)
        #expect(counts[.validateChecksum] == 1)
        #expect(counts[.loadRuleset] == 35)
    }

    /// `ir.md` section 5 step 1: no conformance case can carry
    /// `invalid_encoding`, because a proto3 `string` is valid UTF-8 by
    /// definition, on the wire and in the corpus.
    @Test("No conformance case asks for invalid_encoding")
    func noCaseCarriesInvalidEncoding() throws {
        for testCase in try TesteeHarness.corpus().cases {
            switch testCase.expected.value {
            case .canonicalization(let expected):
                #expect(expected.reasonCode != .invalidEncoding, Comment(rawValue: testCase.id))
            case .validationReport(let expected):
                #expect(expected.format.reasonCode != .invalidEncoding, Comment(rawValue: testCase.id))
                #expect(expected.checksum.reasonCode != .invalidEncoding, Comment(rawValue: testCase.id))
            case .none:
                continue
            }
        }
    }
}

/// The business version `rules.lock` names, read rather than repeated.
enum BusinessIDRulesVersion {
    static let locked: String = {
        guard
            let text = try? String(
                contentsOf: TesteeHarness.root.appending(path: "rules.lock"), encoding: .utf8
            )
        else { return "" }
        return
            text
            .split(separator: "\n")
            .first { $0.hasPrefix("rules_version = ") }
            .map { String($0.split(separator: "\"")[1]) } ?? ""
    }()
}
#endif
