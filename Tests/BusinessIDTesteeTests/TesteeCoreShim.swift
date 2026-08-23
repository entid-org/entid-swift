internal import BusinessIDTestee
package import BusinessIDWire

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
