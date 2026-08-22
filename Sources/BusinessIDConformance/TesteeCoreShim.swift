package import BusinessIDWire

internal import BusinessIDTestee

/// Re-exports the testee entry point for the runner's own tests.
///
/// The runner drives a testee; its tests need to build a correct response
/// before mutating one field of it, which is what proves the comparison is not
/// vacuous.
package enum TesteeCoreShim {
    package static func respond(
        to request: Libbusinessid_Testee_V1_TesteeRequest
    ) -> Libbusinessid_Testee_V1_TesteeResponse {
        TesteeCore.respond(to: request)
    }
}
