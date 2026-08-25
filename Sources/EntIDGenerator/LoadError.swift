/// The two typed refusals of `ir.md` section 10.
///
/// A size, structural, arithmetic or graph violation is `invalid_ruleset`. An
/// unsupported `format_version` and an unknown capability id are
/// `incompatible_ruleset`.
///
/// The distinction is deliberate and is what an operator reads. A bundle that
/// legitimately uses a newer operation declares the capability that introduced
/// it, so a generator too old to understand it stops at check 4 and is told to
/// upgrade. Reaching the opcode check with an unknown operation instead means
/// the bundle used one without declaring it, which is a forged bundle rather
/// than a version gap.
package enum LoadError: Error, Equatable, Sendable, CustomStringConvertible {
    /// A size, structural, arithmetic or graph violation.
    case invalidRuleset(String)
    /// An unsupported `format_version` or an unknown capability id.
    case incompatibleRuleset(String)

    /// The wire name the conformance protocol expects in `ObservedLoad`.
    package var engineErrorName: String {
        switch self {
        case .invalidRuleset: "invalid_ruleset"
        case .incompatibleRuleset: "incompatible_ruleset"
        }
    }

    /// The explanation, without the typed prefix.
    package var reason: String {
        switch self {
        case .invalidRuleset(let reason), .incompatibleRuleset(let reason): reason
        }
    }

    package var description: String { "\(engineErrorName): \(reason)" }
}
