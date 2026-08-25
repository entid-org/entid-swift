// The testee is driven as a subprocess, which no simulator can do, so this
// whole target is compiled out anywhere but macOS rather than skipped at run
// time. A skipped test reads as a passing one in a summary; an absent one does
// not.
#if os(macOS)

import Foundation
import Testing

package import EntIDWire

/// The framing, exercised against the published executable.
///
/// The verdict on conformance is the runner's, not this package's. What these
/// cases cover is the protocol the runner speaks to: a 32 bit little endian
/// length, then the serialized message, strictly one response per request.
@Suite("Testee wire protocol")
struct WireProtocolTests {
    @Test("One response per request, in order, across every operation")
    func framedExchange() throws {
        let cases = try TesteeHarness.corpus().cases
        let sample = [
            cases.first { $0.operation == .canonicalize },
            cases.first { $0.operation == .validate },
            cases.first { $0.operation == .validateFormat },
            cases.first { $0.operation == .validateChecksum },
            // A hostile bundle, so the framing meets a large payload as well as
            // a small one.
            cases.first { $0.operation == .loadRuleset },
        ].compactMap { $0 }
        #expect(sample.count == 5)

        let requests = sample.map(TesteeHarness.request(for:))
        let responses = try TesteeHarness.exchange(requests)

        #expect(responses.count == requests.count)
        for (request, response) in zip(requests, responses) {
            #expect(response.caseID == request.caseID)
        }
    }

    @Test("The whole corpus survives one exchange, message for message")
    func wholeCorpusFrames() throws {
        let requests = try TesteeHarness.corpus().cases.map(TesteeHarness.request(for:))
        let responses = try TesteeHarness.exchange(requests)
        #expect(responses.count == requests.count)
        for (request, response) in zip(requests, responses) {
            #expect(response.caseID == request.caseID)
            #expect(response.result != nil, Comment(rawValue: "\(request.caseID) produced no result"))
        }
    }

    @Test("A response frame decodes to what the in-process testee produces")
    func wireAgreesWithInProcess() throws {
        // The executable is a stdin and stdout loop around `TesteeCore`. If the
        // two ever disagree, the framing is dropping or reordering something.
        let requests = try TesteeHarness.corpus().cases.map(TesteeHarness.request(for:))
        for (request, response) in zip(requests, try TesteeHarness.exchange(requests)) {
            #expect(
                response == TesteeCoreShim.respond(to: request),
                Comment(rawValue: request.caseID)
            )
        }
    }

    @Test("An empty input closes the loop instead of hanging")
    func emptyInput() throws {
        #expect(try TesteeHarness.exchange([]).isEmpty)
    }
}

#endif
