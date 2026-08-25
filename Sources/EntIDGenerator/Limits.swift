/// The normative execution and structural limits of `ir.md` section 8.
///
/// Every limit is normative. An engine may raise an internal limit, never
/// lower it. The bundle shaped limits are enforced here, when the bundle is
/// accepted by the generator, and no longer apply once code has been emitted.
/// The user input limit is an obligation of the engine itself and lives with
/// the shipped runtime instead.
package enum Limits {
    // MARK: Structural

    package static let maximumBundleBytes = 16_777_216
    package static let maximumIdentifiers = 10000
    package static let maximumTotalNodes = 500_000
    package static let maximumNodesPerProgram = 4096
    package static let maximumCallDepth = 32
    package static let maximumConstantBytes = 4096
    package static let maximumUserInputBytes = 1024
    package static let evaluationBudget = 100_000
    package static let codePointsBilledAsOneStep = 64
    package static let maximumCapturesPerFormat = 128

    // MARK: Arithmetic

    package static let modulusRange: ClosedRange<Int64> = 2...1_000_000_000
    package static let weightMagnitudeRange: ClosedRange<Int64> = 0...1_000_000
    package static let weightCountRange: ClosedRange<Int> = 1...256
    package static let remainderMapCountRange: ClosedRange<Int> = 1...1_000_000
    package static let indexRange: ClosedRange<Int64> = 0...4096
    package static let comparisonConstantRange: ClosedRange<Int64> = -1_000_000_000...1_000_000_000
    package static let concatOperandRange: ClosedRange<Int> = 1...256
    package static let provableDigitsRange: ClosedRange<Int> = 1...18
    package static let customAlphabetRange: ClosedRange<Int> = 1...256

    // MARK: Header

    /// `ir.md` check 6: `rules_version` is non empty, at most 64 bytes, and
    /// made only of ASCII letters, digits, dot, dash and underscore.
    package static let maximumRulesVersionBytes = 64
}
