// The testee is driven as a subprocess, which no simulator can do, so this
// whole target is compiled out anywhere but macOS rather than skipped at run
// time. A skipped test reads as a passing one in a summary; an absent one does
// not.
#if os(macOS)

internal import EntIDTestee
package import EntIDWire

/// The in-process entry point, reached from the tests.
///
/// The executable is a stdin and stdout loop around this; comparing the two is
/// how the framing is checked without a second implementation of the engine.
enum TesteeCoreShim {
    static func respond(
        to request: Libbusinessid_Testee_V1_TesteeRequest
    ) -> Libbusinessid_Testee_V1_TesteeResponse {
        TesteeCore.respond(to: request)
    }
}
#endif
