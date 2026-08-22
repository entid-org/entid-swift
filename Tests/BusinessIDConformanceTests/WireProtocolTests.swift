// The testee is driven as a subprocess, which only the host platform can do.
// The rest of the corpus runs in process and does run on a simulator, so the
// engine itself is still exercised there — what is skipped is the framing, not
// a conformance case.
#if os(macOS)

package import BusinessIDWire
import Foundation
import Testing

@testable import BusinessIDConformance

/// The testee over the real wire, as a subprocess.
///
/// The rest of the conformance suite drives the testee in process, which is
/// fast and hermetic but proves nothing about the framing. These cases run the
/// published executable exactly as the runner does: a 32 bit little endian
/// length, then the serialized message, strictly one response per request.
@Suite("Testee wire protocol")
struct WireProtocolTests {
    /// The built testee, found in the package build directory.
    ///
    /// `Bundle.main` inside an XCTest bundle points at the test runner, not at
    /// the package products, so the search starts from this file instead. CI
    /// sets `BUSINESSID_TESTEE` and skips the search entirely.
    static func testeeURL() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["BUSINESSID_TESTEE"] {
            return URL(fileURLWithPath: override)
        }
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".build")
        let manager = FileManager.default
        var candidates: [URL] = []
        let triples = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for triple in triples {
            for configuration in ["debug", "release"] {
                let candidate = triple.appending(path: configuration).appending(path: "businessid-testee")
                if manager.isExecutableFile(atPath: candidate.path) { candidates.append(candidate) }
            }
        }
        guard let newest = candidates.max(by: { modified($0) < modified($1) }) else {
            throw TesteeUnavailable()
        }
        return newest
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    struct TesteeUnavailable: Error, CustomStringConvertible {
        var description: String {
            "businessid-testee was not found beside the test bundle; "
                + "build it or set BUSINESSID_TESTEE"
        }
    }

    static func frame(_ payload: [UInt8]) -> Data {
        let length = UInt32(payload.count)
        return Data(
            [
                UInt8(truncatingIfNeeded: length),
                UInt8(truncatingIfNeeded: length >> 8),
                UInt8(truncatingIfNeeded: length >> 16),
                UInt8(truncatingIfNeeded: length >> 24),
            ] + payload)
    }

    static func unframe(_ data: Data) -> [[UInt8]] {
        var messages: [[UInt8]] = []
        var offset = data.startIndex
        while data.distance(from: offset, to: data.endIndex) >= 4 {
            let header = data[offset..<data.index(offset, offsetBy: 4)]
            let bytes = [UInt8](header)
            let length =
                Int(bytes[0]) | Int(bytes[1]) << 8 | Int(bytes[2]) << 16 | Int(bytes[3]) << 24
            let start = data.index(offset, offsetBy: 4)
            guard data.distance(from: start, to: data.endIndex) >= length else { break }
            messages.append([UInt8](data[start..<data.index(start, offsetBy: length)]))
            offset = data.index(start, offsetBy: length)
        }
        return messages
    }

    /// Sends every request through one subprocess and returns the responses.
    static func exchange(
        _ requests: [Libbusinessid_Testee_V1_TesteeRequest]
    ) throws -> [Libbusinessid_Testee_V1_TesteeResponse] {
        let process = Process()
        process.executableURL = try testeeURL()
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()

        var payload = Data()
        for request in requests { payload += frame(try request.serializedBytes()) }
        try input.fileHandleForWriting.write(contentsOf: payload)
        try input.fileHandleForWriting.close()

        let raw = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        return try unframe(raw).map {
            try Libbusinessid_Testee_V1_TesteeResponse(serializedBytes: $0)
        }
    }

    @Test("A framed exchange returns one response per request, in order")
    func framedExchange() throws {
        let runner = try ConformanceRunner(corpusPath: ConformanceTests.corpusPath())
        // A spread across every operation, including a hostile bundle, so the
        // framing is exercised on a large payload as well as a small one.
        let sample = [
            runner.corpus.cases.first { $0.operation == .canonicalize },
            runner.corpus.cases.first { $0.operation == .validate },
            runner.corpus.cases.first { $0.operation == .validateFormat },
            runner.corpus.cases.first { $0.operation == .validateChecksum },
            runner.corpus.cases.first { $0.operation == .loadRuleset },
        ].compactMap { $0 }
        #expect(sample.count == 5)

        let requests = sample.map(runner.request(for:))
        let responses = try Self.exchange(requests)

        #expect(responses.count == requests.count)
        for (request, response) in zip(requests, responses) {
            #expect(response.caseID == request.caseID)
        }
    }

    @Test("The subprocess agrees with the in process testee on the whole corpus")
    func subprocessAgreesWithInProcess() throws {
        let runner = try ConformanceRunner(corpusPath: ConformanceTests.corpusPath())
        let requests = runner.corpus.cases.map(runner.request(for:))
        let overWire = try Self.exchange(requests)

        #expect(overWire.count == requests.count)
        for (request, response) in zip(requests, overWire) {
            #expect(response == TesteeCoreShim.respond(to: request), Comment(rawValue: request.caseID))
        }
    }

    @Test("The whole corpus passes over the wire, not only in process")
    func corpusOverTheWire() throws {
        let runner = try ConformanceRunner(corpusPath: ConformanceTests.corpusPath())
        var responses: [String: Libbusinessid_Testee_V1_TesteeResponse] = [:]
        let requests = runner.corpus.cases.map(runner.request(for:))
        for (request, response) in zip(requests, try Self.exchange(requests)) {
            responses[request.caseID] = response
        }

        let outcome = try runner.run { request in
            guard let response = responses[request.caseID] else {
                Issue.record("no response for \(request.caseID)")
                return Libbusinessid_Testee_V1_TesteeResponse()
            }
            return response
        }
        for divergence in outcome.divergences.prefix(10) {
            Issue.record(Comment(rawValue: divergence.summary))
        }
        #expect(outcome.divergences.isEmpty)
        #expect(outcome.executed == 665)
    }
}

#endif
