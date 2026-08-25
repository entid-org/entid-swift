import Foundation
import Testing

@testable import EntID

/// `Predicates.prefixIn`, which `engine.md` section 14 requires to be sublinear
/// in the size of the list.
///
/// The published bundle cannot prove this suite right. Its `prefix_in` nodes
/// hold one element length each — 1748 of five, 818 of six, 148 of four, 41 of
/// two — so the blocking by length is a no-op on them and every conformance
/// case would pass against a search that mishandles a mixed table.
///
/// Reporting that is what closed the hole: since `2026.09.2` a bundle mixing
/// element lengths in one `prefix_in` is refused at load, and a rule needing two
/// lengths writes one `prefix_in` per length under an `any`. So the mixed table
/// these tests exercise is a shape this engine can no longer be handed.
///
/// They stay, and since `2026.08.32` that is not this engine's judgement but a
/// requirement. `ir.md` says the refusal takes its own evidence with it: no
/// conformance case can distinguish a search run per length from one run over
/// the whole table, because the shape that separates them is the shape the
/// loader refuses. An engine MUST therefore pin the semantics below its loader,
/// by a native test comparing its search against the definition transcribed
/// literally — some element is a prefix of the subject — over tables of mixed
/// lengths. That is `agreesWithAScan`, and it is the second rule the corpus
/// cannot carry, alongside `invalid_encoding`.
///
/// The independent reason still holds: the load check and the search are two
/// pieces of code that can drift apart, and this suite is what notices if the
/// first is relaxed while the second still assumes it.
@Suite("Prefix membership")
struct PrefixMembershipTests {
    /// The order the generator emits: length first, code points second.
    static func table(_ values: [String]) -> [[Unicode.Scalar]] {
        values
            .sorted { left, right in
                let first = Array(left.unicodeScalars)
                let second = Array(right.unicodeScalars)
                if first.count != second.count { return first.count < second.count }
                for (one, other) in zip(first, second) where one.value != other.value {
                    return one.value < other.value
                }
                return false
            }
            .map { Array($0.unicodeScalars) }
    }

    static func view(_ text: String) -> ScalarView { ScalarView(Array(text.unicodeScalars)) }

    /// What the predicate means, stated as the obvious loop.
    static func scan(_ value: String, _ values: [String]) -> Bool {
        values.contains { !$0.isEmpty && value.hasPrefix($0) }
    }

    @Test("A shorter entry is found even when a longer one sorts nearer the value")
    func theTrapASingleBinarySearchFallsInto() {
        // Searching the whole table for the greatest entry not exceeding "ABC"
        // yields "AA", which is not a prefix of it — and "A", which is, never
        // gets looked at. Only a search at a fixed length answers this.
        let values = Self.table(["A", "AA"])
        #expect(Predicates.prefixIn(Self.view("ABC"), values))
        #expect(Predicates.prefixIn(Self.view("AA"), values))
        #expect(!Predicates.prefixIn(Self.view("B"), values))
    }

    @Test("Every length in a mixed table is searched")
    func mixedLengths() {
        let values = Self.table(["B1000", "9A0000", "ZZ", "K1101R", "0101"])
        for hit in ["B1000X", "9A0000", "ZZTOP", "K1101R.HRB1", "0101ABC"] {
            #expect(Predicates.prefixIn(Self.view(hit), values), Comment(rawValue: hit))
        }
        for miss in ["B1001", "9A0001", "ZY", "K1101S", "0102", "", "Z"] {
            #expect(!Predicates.prefixIn(Self.view(miss), values), Comment(rawValue: miss))
        }
    }

    /// A table the loader accepts and whose blocks are not all one size.
    ///
    /// `ir.md` states the element length in UTF-8 bytes, and allows an engine
    /// working in another unit to group more finely. This engine groups by code
    /// point count, so `["PZ", "é"]` — two bytes each, two code points and one —
    /// reaches the search as two blocks. It is the one shape a bundle may still
    /// carry that exercises the block walk.
    @Test("A byte-equal table with two code point lengths is searched correctly")
    func equalBytesUnequalCodePoints() {
        let values = Self.table(["PZ", "\u{00E9}"])
        #expect(values.map(\.count) == [1, 2], "one block of one code point, one of two")
        for hit in ["PZ", "PZX", "\u{00E9}", "\u{00E9}X"] {
            #expect(Predicates.prefixIn(Self.view(hit), values), Comment(rawValue: hit))
        }
        for miss in ["P", "QQ", "\u{00E8}", ""] {
            #expect(!Predicates.prefixIn(Self.view(miss), values), Comment(rawValue: miss))
        }
    }

    @Test("An absent view and an empty table are both false")
    func absentAndEmpty() {
        #expect(!Predicates.prefixIn(.absent, Self.table(["A"])))
        #expect(!Predicates.prefixIn(Self.view("A"), []))
        #expect(!Predicates.prefixIn(.absent, []))
    }

    @Test("A view shorter than every entry matches nothing")
    func viewShorterThanEveryEntry() {
        let values = Self.table(["ABCD", "ABCE"])
        #expect(!Predicates.prefixIn(Self.view("ABC"), values))
        #expect(Predicates.prefixIn(Self.view("ABCD"), values))
    }

    /// The guard that stands in for the conformance cases a mixed table has
    /// none of: thousands of tables and values, compared against the loop the
    /// predicate is supposed to be equivalent to.
    @Test("The search agrees with a scan on every table and value tried")
    func agreesWithAScan() {
        var random = SeededGenerator(seed: 0xC0FF_EE01)
        let alphabet = Array("AB01")
        func word(_ length: Int) -> String {
            String((0..<length).map { _ in alphabet[Int(random.next() % UInt64(alphabet.count))] })
        }

        for _ in 0..<400 {
            let size = 1 + Int(random.next() % 12)
            var values: Set<String> = []
            while values.count < size { values.insert(word(1 + Int(random.next() % 4))) }
            let sorted = Array(values).sorted()
            let table = Self.table(sorted)

            for _ in 0..<12 {
                let candidate = word(Int(random.next() % 6))
                #expect(
                    Predicates.prefixIn(Self.view(candidate), table) == Self.scan(candidate, sorted),
                    Comment(rawValue: "\(candidate.debugDescription) against \(sorted)")
                )
            }
        }
    }

    /// Section 14's goal, held as a count rather than as a duration.
    ///
    /// A timing is not a property: it moves with the machine and it passes on a
    /// fast one. The number of comparisons does not. A scan of n entries makes
    /// n of them; this asserts a logarithmic budget, and the margin is wide
    /// enough that only a scan can break it.
    @Test("A membership test is logarithmic in the size of the list")
    func probesAreLogarithmic() {
        // One block of 4096 five-character entries, the shape the German court
        // table has, an order of magnitude larger.
        let values = Self.table((0..<4096).map { String(format: "%05d", $0) })
        #expect(values.count == 4096)

        // Present, absent below every entry, absent above, and absent in the
        // middle: the four places a search can end.
        for candidate in ["02048X", "00000", "04095", "99999", "02047"] {
            var probes = 0
            _ = Predicates.prefixIn(Self.view(candidate), values, probes: &probes)
            // 4096 entries: 12 steps to bound the block, 12 to search it, plus
            // slack. A scan would take up to 4096.
            #expect(probes <= 30, Comment(rawValue: "\(candidate): \(probes) probes"))
        }
    }

    /// The same property on the tables actually shipped, not only on a
    /// synthetic one.
    ///
    /// `p0`, `p1` and `p2` are the German five-character, German six-character
    /// and French greffe memberships of this release. The names are the
    /// generator's numbering: a later bundle may renumber them, and the compile
    /// error that follows is the prompt to re-point this test rather than a
    /// reason to delete it.
    @Test("The shipped membership tables are blocked, ordered, and searched in a few probes")
    func theShippedTables() {
        let tables = [
            ("p0", GeneratedLiterals.p0, 1748, 5),
            ("p1", GeneratedLiterals.p1, 818, 6),
            ("p2", GeneratedLiterals.p2, 148, 4),
        ]
        for (name, table, count, length) in tables {
            #expect(table.count == count, Comment(rawValue: name))
            #expect(table.allSatisfy { $0.count == length }, Comment(rawValue: name))
            // The order `prefixIn` depends on: length first, code points second.
            let ordered = zip(table, table.dropFirst()).allSatisfy { left, right in
                if left.count != right.count { return left.count < right.count }
                for (a, b) in zip(left, right) where a.value != b.value { return a.value < b.value }
                return false
            }
            #expect(ordered, Comment(rawValue: "\(name) is not in the emitted order"))

            // A code that is in no table is the input the cost falls on.
            var probes = 0
            let absent = Self.view(String(repeating: "Z", count: length))
            #expect(!Predicates.prefixIn(absent, table), Comment(rawValue: name))
            _ = Predicates.prefixIn(absent, table, probes: &probes)
            #expect(probes <= 26, Comment(rawValue: "\(name): \(probes) probes over \(count) entries"))
        }
    }

    /// The shape changed, not the constant.
    ///
    /// A single fast number proves little: a scan of a short list is fast too.
    /// The two German tables differ 2.14x in size — 1748 five-character codes
    /// against 818 six-character ones — so a scan would show that ratio in its
    /// cost, and a logarithmic search shows log2(1748)/log2(818) = 1.11.
    /// Comparing the two tables to each other is what separates the two shapes,
    /// and it needs no clock.
    @Test("Cost tracks the logarithm of the list, not its length")
    func costTracksTheLogarithm() {
        func probes(_ table: [[Unicode.Scalar]], _ length: Int) -> Int {
            var count = 0
            _ = Predicates.prefixIn(Self.view(String(repeating: "Z", count: length)), table, probes: &count)
            return count
        }
        let large = probes(GeneratedLiterals.p0, 5)
        let small = probes(GeneratedLiterals.p1, 6)
        let sizeRatio = Double(GeneratedLiterals.p0.count) / Double(GeneratedLiterals.p1.count)
        let probeRatio = Double(large) / Double(small)

        let logRatio =
            log2(Double(GeneratedLiterals.p0.count)) / log2(Double(GeneratedLiterals.p1.count))

        #expect(sizeRatio > 2.0, Comment(rawValue: "the tables must differ enough to tell the shapes apart"))
        // No magic constant: the claim is that the cost follows the logarithm
        // and not the length, so the measured ratio must sit nearer the one
        // than the other. A scan would land on the size ratio exactly.
        #expect(
            abs(probeRatio - logRatio) < abs(probeRatio - sizeRatio),
            Comment(
                rawValue: "probes \(large)/\(small) = \(probeRatio), "
                    + "log ratio \(logRatio), size ratio \(sizeRatio)")
        )
    }

    @Test("The probe count is what the search actually did")
    func probeCountIsNotVacuous() {
        // A table of one entry cannot need more than a couple of comparisons,
        // and it must need at least one: a counter wired to nothing would
        // report zero here and still pass the budget above.
        var probes = 0
        #expect(Predicates.prefixIn(Self.view("AB"), Self.table(["A"]), probes: &probes))
        #expect(probes >= 1)
        #expect(probes <= 4)
    }
}

/// A seeded generator, so a failing table is reproducible from the seed.
struct SeededGenerator {
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
