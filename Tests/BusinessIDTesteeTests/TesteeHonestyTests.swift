// The testee is driven as a subprocess, which no simulator can do, so this
// whole target is compiled out anywhere but macOS rather than skipped at run
// time. A skipped test reads as a passing one in a summary; an absent one does
// not.
#if os(macOS)

package import BusinessIDWire
import Foundation
import Testing

/// The testee does not cheat.
///
/// The runner is the only program that reads an expected result, and it comes
/// from the specification repository pinned to the commit `rules.lock` records.
/// This package writes the testee, and `engine.md` section 11.3 states the form
/// the proof has to take: five observable properties, because an intention
/// cannot be tested.
///
/// | What is asserted | What it excludes |
/// | --- | --- |
/// | the testee names neither the corpus nor anything that reads one | reading the expectations directly |
/// | it reaches no file system | the corpus is a file; whoever opens nothing reads none |
/// | it answers identically whatever the case identifier — plausible, absurd, empty | recognising a case |
/// | it answers identically whatever the order of the requests | behaviour that depends on history |
/// | it answers identically to a repeated request | non determinism |
///
/// **This suite opens no corpus.** Section 11.3 requires the requests to be
/// invented on the spot: a proof that the testee never reads the corpus, built
/// out of the corpus, demonstrates the opposite of what it asserts. Every
/// request below is written here; the values are quoted from a conformance case
/// named in the comment above them, which is how this package sources an
/// identifier without opening anything at run time.
///
/// What the corpus itself carries is asserted in `CorpusShapeTests`, which is
/// not a proof about the testee and says so by living elsewhere.
@Suite("The testee does not cheat")
struct TesteeHonestyTests {
    // MARK: - Requests invented here

    /// `siren-validate-format-050`.
    static let validSIREN = "012345674"
    /// `siren-validate-format-invalid-051`.
    static let shortSIREN = "01234567"
    /// `siren-validate-checksum-052`.
    static let badChecksumSIREN = "012345675"
    /// `dispatch-country-mismatch-004`.
    static let belgianVAT = "BE0123456749"

    static func request(
        _ caseID: String,
        _ operation: Libbusinessid_Conformance_V1_Operation,
        kind: String,
        input: String,
        countryCode: String? = nil
    ) -> Libbusinessid_Testee_V1_TesteeRequest {
        var request = Libbusinessid_Testee_V1_TesteeRequest()
        request.caseID = caseID
        request.operation = operation
        request.kind = kind
        request.input = input
        if let countryCode { request.countryCode = countryCode }
        return request
    }

    /// A set covering every operation of the protocol, including the two that
    /// answer with a failure rather than an observation.
    ///
    /// It is deliberately varied — valid, invalid, unknown kind, explicit
    /// country, a bundle that cannot load — because a testee that adapted to
    /// the case would have more room to do so here than on one shape repeated.
    static var invented: [Libbusinessid_Testee_V1_TesteeRequest] {
        var requests: [Libbusinessid_Testee_V1_TesteeRequest] = [
            request("invented-1", .validate, kind: "siren", input: validSIREN),
            request("invented-2", .validate, kind: "siren", input: shortSIREN),
            request("invented-3", .validate, kind: "siren", input: badChecksumSIREN),
            request("invented-4", .validateFormat, kind: "siren", input: validSIREN),
            request("invented-5", .validateChecksum, kind: "siren", input: badChecksumSIREN),
            request("invented-6", .canonicalize, kind: "siren", input: "  012 345-674  "),
            request("invented-7", .validate, kind: "vat", input: belgianVAT, countryCode: "FR"),
            request("invented-8", .validate, kind: "no_such_kind", input: "whatever"),
            request("invented-9", .validate, kind: "siren", input: ""),
            request("invented-10", .canonicalize, kind: "", input: ""),
            request("invented-11", .unspecified, kind: "siren", input: validSIREN),
        ]
        // Bytes that are not a rule bundle, so the answer is a refusal rather
        // than an acceptance, and it needs no bundle to be carried here.
        var load = request("invented-12", .loadRuleset, kind: "siren", input: "")
        load.rulesPayload = Data([0xFF, 0xFF, 0xFF, 0xFF])
        requests.append(load)
        return requests
    }

    // MARK: - It cannot read the corpus

    /// The testee's own code, with comments removed.
    ///
    /// Comments are stripped because the testee's documentation says, in
    /// words, that it does not read the corpus — and a check that failed on
    /// the sentence describing the property would be a check nobody could
    /// keep. What is scanned is what compiles.
    static func testeeSources() throws -> [(name: String, code: String)] {
        var files: [(String, String)] = []
        for directory in ["Sources/BusinessIDTestee", "Sources/businessid-testee"] {
            let url = TesteeHarness.root.appending(path: directory)
            let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
            for case let file as URL in walker ?? .init() where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                files.append((file.lastPathComponent, strippingComments(text)))
            }
        }
        return files
    }

    static func strippingComments(_ text: String) -> String {
        var out = ""
        var depth = 0
        var index = text.startIndex
        while index < text.endIndex {
            let rest = text[index...]
            if rest.hasPrefix("/*") {
                depth += 1
                index = text.index(index, offsetBy: 2)
                continue
            }
            if rest.hasPrefix("*/"), depth > 0 {
                depth -= 1
                index = text.index(index, offsetBy: 2)
                continue
            }
            if depth == 0, rest.hasPrefix("//") {
                while index < text.endIndex, text[index] != "\n" { index = text.index(after: index) }
                continue
            }
            if depth == 0 { out.append(text[index]) }
            index = text.index(after: index)
        }
        return out
    }

    @Test("The testee names no expectation type and no corpus")
    func noExpectationInTheSource() throws {
        // Reaching an expected result is the one thing that would let this
        // package grade itself. None of these names may appear.
        // Type names and a file name, none of which can collide with
        // something innocent.
        let forbidden = [
            "ConformanceBundle", "ConformanceCase", "ExpectedOutcome", "ExpectedValidationReport",
            "ExpectedCanonicalization", "ExpectedStep", "expectedEngineError", "expected",
            "businessid-conformance",
        ]
        let sources = try Self.testeeSources()
        #expect(!sources.isEmpty, "the testee sources were not found")
        for file in sources {
            for token in forbidden {
                #expect(
                    !file.code.contains(token),
                    Comment(rawValue: "\(file.name) mentions \(token)")
                )
            }
        }
    }

    @Test("The testee opens no file of its own")
    func opensNoFile() throws {
        // It reads standard input and writes standard output. Anything that
        // opens a path is a way to reach something it was not handed.
        let opening = [
            "FileManager", "Bundle.module", "String(contentsOf", "Data(contentsOf",
            "contentsOfFile", "URL(fileURLWithPath", "Process(",
        ]
        for file in try Self.testeeSources() {
            for token in opening {
                #expect(
                    !file.code.contains(token),
                    Comment(rawValue: "\(file.name) mentions \(token)")
                )
            }
        }
    }

    /// The same clause, said to a reader who does not trust source inspection:
    /// the corpus sits under the repository root, so a testee run from a
    /// directory that holds none has nothing to open.
    @Test("The testee answers the same from a directory holding no corpus")
    func answersTheSameAnywhere() throws {
        let requests = Self.invented
        let fromRepository = try TesteeHarness.exchange(requests)

        // The set has to exercise something. Comparing twelve failures would
        // compare nothing, and would keep passing if the requests degenerated.
        var shapes: Set<String> = []
        for response in fromRepository {
            switch response.result {
            case .validationReport: shapes.insert("report")
            case .canonicalization: shapes.insert("canonicalization")
            case .load: shapes.insert("load")
            case .failure: shapes.insert("failure")
            case .none: shapes.insert("none")
            }
        }
        #expect(shapes == ["report", "canonicalization", "load", "failure"])

        let empty = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "businessid-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        let fromNowhere = try TesteeHarness.exchange(requests, workingDirectory: empty)

        #expect(fromRepository.count == requests.count)
        #expect(fromNowhere == fromRepository)
    }

    // MARK: - It cannot adapt to the case

    @Test("The case identifier changes nothing but the echo")
    func caseIdentifierIsOnlyEchoed() throws {
        // The identifier exists so a desynchronized exchange is detected rather
        // than silently scoring the wrong case. A testee that consulted it
        // could answer one way for a case it recognises and another for the
        // rest.
        let base = Self.request("invented-1", .validate, kind: "siren", input: Self.validSIREN)

        // Plausible identifiers, shaped exactly like the corpus writes them;
        // absurd ones; and the empty one.
        let borrowed = [
            "siren-validate-format-050",
            "siren-validate-format-invalid-051",
            "loader-truncated-001",
            "dispatch-country-mismatch-004",
            "vat-be-validate-001",
            "unknown",
            "invented-1-x",
            "../../nowhere/at/all",
            "🙂",
            String(repeating: "z", count: 4096),
            "",
        ]

        var disguises: [Libbusinessid_Testee_V1_TesteeRequest] = []
        for identifier in borrowed {
            var disguised = base
            disguised.caseID = identifier
            disguises.append(disguised)
        }

        let responses = try TesteeHarness.exchange(disguises)
        #expect(responses.count == disguises.count)
        for (request, response) in zip(disguises, responses) {
            #expect(response.caseID == request.caseID, "the identifier is echoed")
            var stripped = response
            stripped.caseID = ""
            var reference = try #require(responses.first)
            reference.caseID = ""
            #expect(stripped == reference, Comment(rawValue: "answer changed for id \(request.caseID)"))
        }
    }

    @Test("The order requests arrive in changes nothing")
    func orderChangesNothing() throws {
        // A testee that kept state between requests could answer correctly only
        // in the order it happened to be given.
        let requests = Self.invented

        var inOrder: [String: Libbusinessid_Testee_V1_TesteeResponse] = [:]
        for response in try TesteeHarness.exchange(requests) { inOrder[response.caseID] = response }
        #expect(inOrder.count == requests.count, "the case identifiers are distinct")

        var seeded = SplitMix(seed: 0x5EED_1234)
        var shuffled = requests
        for index in stride(from: shuffled.count - 1, to: 0, by: -1) {
            shuffled.swapAt(index, Int(seeded.next() % UInt64(index + 1)))
        }

        for response in try TesteeHarness.exchange(shuffled) {
            #expect(inOrder[response.caseID] == response, Comment(rawValue: response.caseID))
        }
    }

    @Test("Repeating one request produces one identical answer each time")
    func repetitionIsStable() throws {
        let request = Self.request("invented-1", .validate, kind: "siren", input: Self.validSIREN)
        let responses = try TesteeHarness.exchange(Array(repeating: request, count: 25))
        #expect(responses.count == 25)
        for response in responses { #expect(response == responses[0]) }
    }

    // MARK: - And neither does this suite

    /// The clause that closes section 11.3, kept true by measurement rather
    /// than by the paragraph above claiming it.
    ///
    /// This suite used to build its requests out of the corpus, which is the
    /// drift the clause names. Reading its own text is the cheapest thing that
    /// notices the drift coming back.
    @Test("The honesty suite opens no corpus either")
    func thisSuiteOpensNoCorpus() throws {
        // Two routes, and nothing else can reach the file: the harness reader,
        // or a path this suite builds itself.
        //
        // Each token is assembled from two pieces, because a scanner that
        // spelled them out would find itself and fail against a suite that is
        // clean — and neither token may appear as data elsewhere in the file,
        // which is why `businessid-conformance` alone is not one of them: it is
        // in the list `noExpectationInTheSource` scans the testee for.
        let forbidden = [
            "TesteeHarness." + "corpus",
            "spec/businessid-" + "conformance",
        ]
        let text = try String(contentsOf: URL(fileURLWithPath: #filePath), encoding: .utf8)
        let code = Self.strippingComments(text)
        for token in forbidden {
            #expect(!code.contains(token), Comment(rawValue: "the honesty suite reaches \(token)"))
        }
    }
}

/// A seeded shuffle, so a failing order is reproducible.
struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
#endif
