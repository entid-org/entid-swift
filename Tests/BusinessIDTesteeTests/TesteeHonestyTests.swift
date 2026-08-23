package import BusinessIDWire
import Foundation
import Testing

/// The testee does not cheat.
///
/// The runner is the only program that reads an expected result, and it comes
/// from the specification repository pinned to the commit `rules.lock` records.
/// This package writes the testee, and these cases are what make the absence of
/// cheating something a reader can check rather than something a README claims:
/// the testee does not read the corpus, does not interpret an expectation, and
/// does not behave differently depending on which case it was handed.
///
/// This suite reads the corpus, on purpose. The point is that the code under
/// test cannot.
@Suite("The testee does not cheat")
struct TesteeHonestyTests {
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

    @Test("The testee answers the same from a directory holding no corpus")
    func answersTheSameAnywhere() throws {
        // Source inspection says it does not read the corpus; this says the
        // same thing to a reader who does not trust source inspection.
        let cases = try TesteeHarness.corpus().cases
        let sample = Array(cases.prefix(60)) + Array(cases.suffix(40))
        let requests = sample.map(TesteeHarness.request(for:))

        let fromRepository = try TesteeHarness.exchange(requests)

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
        let cases = try TesteeHarness.corpus().cases
        let subject = try #require(cases.first { $0.operation == .validate })
        let base = TesteeHarness.request(for: subject)

        var disguises: [Libbusinessid_Testee_V1_TesteeRequest] = []
        // Identifiers of other cases, of cases expecting the opposite verdict,
        // and identifiers that name nothing at all.
        let borrowed =
            cases.prefix(40).map(\.id) + ["", "unknown", subject.id + "-x", "loader-truncated-001"]
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
        // in the order the corpus happens to be written.
        let cases = Array(try TesteeHarness.corpus().cases.prefix(120))
        let requests = cases.map(TesteeHarness.request(for:))

        var inOrder: [String: Libbusinessid_Testee_V1_TesteeResponse] = [:]
        for response in try TesteeHarness.exchange(requests) { inOrder[response.caseID] = response }

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
        let subject = try #require(try TesteeHarness.corpus().cases.first { $0.operation == .validate })
        let request = TesteeHarness.request(for: subject)
        let responses = try TesteeHarness.exchange(Array(repeating: request, count: 25))
        #expect(responses.count == 25)
        for response in responses { #expect(response == responses[0]) }
    }

    // MARK: - The corpus itself

    @Test("The corpus carries what this release says it carries")
    func corpusShape() throws {
        // The runner runs whatever the corpus holds, so a case disappearing
        // would pass silently. This is the tripwire for that.
        let corpus = try TesteeHarness.corpus()
        #expect(corpus.rulesVersion == BusinessIDRulesVersion.locked)
        #expect(corpus.cases.count == 666)

        var counts: [Libbusinessid_Conformance_V1_Operation: Int] = [:]
        for testCase in corpus.cases { counts[testCase.operation, default: 0] += 1 }
        #expect(counts[.canonicalize] == 13)
        #expect(counts[.validate] == 614)
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
