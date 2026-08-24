package import BusinessIDWire
import Testing

@testable import BusinessIDGenerator

/// Check 13's clause on the shape of a parameter list: the order `ir.md`
/// section 9 states, then the single element length of a `prefix_in`, in that
/// order.
///
/// Split out of `LoadCheckTests` when that file passed its length limit. It is
/// a coherent group on its own: three rules, each of which a loader can hold in
/// a unit that suits it rather than the one the specification states, and each
/// of which the published bundle cannot exercise.
@Suite("Parameter list shape")
struct ParameterListShapeTests {
    private func load(
        _ mutate: (inout BundleBuilder.Bundle) -> Void = { _ in }
    ) throws -> Result<
        LoadedBundle, LoadError
    > {
        var bundle = BundleBuilder.minimal()
        mutate(&bundle)
        let bytes = try BundleBuilder.bytes(bundle)
        do {
            return .success(try RuleBundleLoader.load(bytes))
        } catch {
            return .failure(error)
        }
    }

    private func expectRefused(
        _ expected: LoadError,
        _ comment: Comment,
        _ mutate: (inout BundleBuilder.Bundle) -> Void
    ) throws {
        switch try load(mutate) {
        case .success:
            Issue.record(comment)
        case .failure(let error):
            #expect(error.engineErrorName == expected.engineErrorName, comment)
        }
    }

    /// `ir.md` section 9 puts `PredicateOperation.lengths` and `values` under the
    /// declared order — ascending, deduplicated — and check 13 has named it
    /// since `2026.09.1`. The reference loader was not enforcing it, and three
    /// shapes passed there: descending, duplicated, and equal keys out of order.
    ///
    /// The corpus fixture carries the first shape only. All three are asserted
    /// here, on both parameter lists, because the omission is invisible while a
    /// lookup is a scan and load bearing the moment it is a binary search.
    @Test(
        "Every shape of a mis-ordered length list is refused",
        arguments: [[9, 3], [3, 3], [3, 9, 9], [9, 9, 3]]
    )
    func unsortedLengths(_ lengths: [UInt32]) throws {
        try expectRefused(.invalidRuleset(""), "lengths are ascending and deduplicated") {
            $0.programs[2].nodes[1] = BundleBuilder.predicate(.lengthIn, inputs: [0]) {
                $0.lengths = lengths
            }
        }
    }

    @Test(
        "Every shape of a mis-ordered prefix list is refused",
        arguments: [["CD", "AB"], ["AB", "AB"], ["AB", "CD", "CD"], ["CD", "CD", "AB"]]
    )
    func unsortedPrefixValues(_ values: [String]) throws {
        try expectRefused(.invalidRuleset(""), "values are ascending and deduplicated") {
            $0.programs[2].nodes[1] = BundleBuilder.predicate(.prefixIn, inputs: [0]) {
                $0.values = values
            }
        }
    }

    /// `ir.md` on `PREDICATE_OP_KIND_PREFIX_IN`, since `2026.09.2`: every element
    /// has the same length, and a bundle mixing lengths is refused.
    ///
    /// The reason is correctness, not speed. Over one sorted list of mixed
    /// lengths a search for the greatest element not after the value answers
    /// wrongly: `["AB", "ABA"]` against `"ABCD"` finds `ABA`, which is not a
    /// prefix, while `AB` is. At one length, starting with an element is
    /// equalling its opening of that length.
    ///
    /// Each list below is correctly ordered and deduplicated, so only the length
    /// rule can refuse it.
    @Test(
        "A prefix list mixing element lengths is refused",
        arguments: [["AB", "ABA"], ["A", "AB"], ["AB", "CD", "EFG"], ["ABC", "AB"].sorted()]
    )
    func mixedLengthPrefixValues(_ values: [String]) throws {
        try expectRefused(.invalidRuleset(""), "one prefix_in holds one element length") {
            $0.programs[2].nodes[1] = BundleBuilder.predicate(.prefixIn, inputs: [0]) {
                $0.values = values
            }
        }
    }

    /// The unit is UTF-8 bytes, and this engine reads it in that unit rather
    /// than in the one that would suit its own search.
    ///
    /// `PZ` and `é` are both two bytes and are not both two code points, so the
    /// two readings disagree on exactly these tables. No conformance case can
    /// separate them — every element of the published bundle is ASCII, where
    /// they agree — which is why both directions are pinned here.
    @Test("Two elements of equal byte length but unequal code point count are accepted")
    func equalBytesUnequalCodePointsIsAccepted() throws {
        // "PZ" is 0x50 0x5A, "é" is 0xC3 0xA9: ascending, two bytes each.
        switch try load({
            $0.programs[2].nodes[1] = BundleBuilder.predicate(.prefixIn, inputs: [0]) {
                $0.values = ["PZ", "\u{00E9}"]
            }
        }) {
        case .failure(let error): Issue.record("\(error)")
        case .success: break
        }
    }

    @Test("Two elements of equal code point count but unequal byte length are refused")
    func equalCodePointsUnequalBytesIsRefused() throws {
        // Both two code points; two bytes against four. A loader reading the
        // rule in code points would accept this, and would be reading the
        // specification in the unit that suited it.
        try expectRefused(.invalidRuleset(""), "the unit is UTF-8 bytes") {
            $0.programs[2].nodes[1] = BundleBuilder.predicate(.prefixIn, inputs: [0]) {
                $0.values = ["PZ", "\u{00E9}\u{00E9}"]
            }
        }
    }

    /// Check 13 states the order of section 9 first and the single element
    /// length second, "in that order". A list breaking both must report the
    /// order, not the length.
    @Test("A list that is both mis-ordered and mixed reports the order")
    func orderIsReportedBeforeLength() throws {
        switch try load({
            $0.programs[2].nodes[1] = BundleBuilder.predicate(.prefixIn, inputs: [0]) {
                $0.values = ["ABA", "AB"]
            }
        }) {
        case .success:
            Issue.record("a list breaking both rules was accepted")
        case .failure(let error):
            #expect(error.reason.contains("ascending and deduplicated"))
            #expect(!error.reason.contains("mixes element lengths"))
        }
    }

    /// The shape a rule needing two lengths is written in, so the refusal above
    /// forbids a spelling and not a capability.
    @Test("Two prefix lists of one length each, under an ANY, are accepted")
    func onePrefixListPerLengthIsAccepted() throws {
        switch try load({
            $0.programs[2].nodes = [
                BundleBuilder.string(.subject),
                BundleBuilder.predicate(.prefixIn, inputs: [0]) { $0.values = ["AB", "CD"] },
                BundleBuilder.predicate(.prefixIn, inputs: [0]) { $0.values = ["ABA", "EFG"] },
                BundleBuilder.predicate(.any, inputs: [1, 2]),
                BundleBuilder.require(3, reason: .empty, messageKey: "test.empty"),
                BundleBuilder.assertionSequence([4]),
            ]
            $0.programs[2].rootNode = 5
        }) {
        case .failure(let error): Issue.record("\(error)")
        case .success: break
        }
    }

    /// The control: the same lists in the declared order are accepted, so the
    /// two above cannot be passing because the builder itself was refused.
    @Test("The same lists in ascending order are accepted")
    func sortedListsAreAccepted() throws {
        switch try load({
            $0.programs[2].nodes[1] = BundleBuilder.predicate(.lengthIn, inputs: [0]) {
                $0.lengths = [3, 9]
            }
        }) {
        case .failure(let error): Issue.record("\(error)")
        case .success: break
        }
        switch try load({
            $0.programs[2].nodes[1] = BundleBuilder.predicate(.prefixIn, inputs: [0]) {
                $0.values = ["AB", "CD"]
            }
        }) {
        case .failure(let error): Issue.record("\(error)")
        case .success: break
        }
    }
}
