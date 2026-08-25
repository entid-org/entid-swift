/// The predicates that need more than a method on a view.
///
/// Every one of them yields `false` on an absent operand, which is the rule for
/// all predicates but `isAbsent`.
enum Predicates {
    static func lengthIn(_ view: ScalarView, _ lengths: [Int]) -> Bool {
        guard !view.isAbsent else { return false }
        return lengths.contains(view.count)
    }

    static func lengthBetween(_ view: ScalarView, _ minimum: Int, _ maximum: Int) -> Bool {
        guard !view.isAbsent else { return false }
        return view.count >= minimum && view.count <= maximum
    }

    /// True when `index` is a valid code point position and the code point
    /// there belongs to the set.
    static func charAtIn(_ view: ScalarView, _ index: Int, _ chars: [Unicode.Scalar]) -> Bool {
        guard let scalar = view[index] else { return false }
        return chars.contains(scalar)
    }

    /// True when the view starts with at least one element of the set.
    ///
    /// `engine.md` section 14 requires a membership test that is not linear in
    /// the size of the list, and the register memberships made that observable:
    /// the German court table alone holds 1748 five-character codes and 818
    /// six-character ones, and the cost falls on the *refused* input, which has
    /// to rule out every entry before answering. A scan measured 7083 ns here
    /// against 2451 ns for an intact identifier.
    ///
    /// The table is emitted sorted by length first and code points second, so
    /// every prefix of one length is a contiguous ordered block. The search
    /// walks the blocks — at most as many as there are distinct prefix lengths,
    /// which is a property of the rule and never of the list — and binary
    /// searches each for the view's own prefix of that length. Blocks are
    /// ascending by length, so the walk stops at the first block longer than
    /// the view.
    ///
    /// A single binary search over the whole table would be wrong. Take
    /// `["A", "AA"]` and the value `"ABC"`: the greatest entry not exceeding
    /// the value is `"AA"`, which is not a prefix of it, while `"A"` is. Only
    /// the search at a fixed length answers that correctly.
    ///
    /// **The order is a precondition, not a hope.** `ir.md` section 9 declares
    /// `PredicateOperation.values` ascending and deduplicated, and check 13
    /// refuses a bundle that is not — `entid-gen` rejects one before a
    /// line of this file is generated. That check is what makes the search
    /// safe: on an unsorted table it does not answer slowly, it answers wrongly.
    /// Measured, by enumerating permutations of `["AA", "BB", "CC", "DD"]`:
    /// `["AA", "BB", "DD", "CC"]` against `"CCX"` returns false where a scan
    /// returns true.
    static func prefixIn(_ view: ScalarView, _ prefixes: [[Unicode.Scalar]]) -> Bool {
        var probes = 0
        return prefixIn(view, prefixes, probes: &probes)
    }

    /// The same, counting the comparisons it makes.
    ///
    /// The count is what a test can hold to: a timing is not a property, and a
    /// scan reintroduced by a later edit would still pass a correctness suite.
    static func prefixIn(
        _ view: ScalarView, _ prefixes: [[Unicode.Scalar]], probes: inout Int
    ) -> Bool {
        guard !view.isAbsent, !prefixes.isEmpty else { return false }
        let available = view.count

        var blockStart = 0
        while blockStart < prefixes.count {
            let length = prefixes[blockStart].count
            // Nothing after this block is shorter, so nothing after it can fit.
            if length > available { return false }
            let blockEnd = firstIndexLonger(than: length, in: prefixes, from: blockStart, probes: &probes)
            if contains(view, prefixes, length: length, in: blockStart..<blockEnd, probes: &probes) {
                return true
            }
            blockStart = blockEnd
        }
        return false
    }

    /// First index at or after `start` whose entry is longer than `length`.
    private static func firstIndexLonger(
        than length: Int, in prefixes: [[Unicode.Scalar]], from start: Int, probes: inout Int
    ) -> Int {
        var low = start
        var high = prefixes.count
        while low < high {
            probes += 1
            let middle = low + (high - low) / 2
            if prefixes[middle].count <= length { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /// Binary search of one equal-length block for the view's prefix.
    private static func contains(
        _ view: ScalarView,
        _ prefixes: [[Unicode.Scalar]],
        length: Int,
        in range: Range<Int>,
        probes: inout Int
    ) -> Bool {
        var low = range.lowerBound
        var high = range.upperBound
        while low < high {
            probes += 1
            let middle = low + (high - low) / 2
            switch compare(prefixes[middle], toPrefixOf: view, length: length) {
            case .same: return true
            case .before: low = middle + 1
            case .after: high = middle
            }
        }
        return false
    }

    /// Declared here rather than taken from Foundation: this library imports
    /// nothing, and a comparison result is not worth the first import.
    private enum Order {
        case before, same, after
    }

    /// Orders one candidate against the first `length` code points of the view.
    ///
    /// Code point order and UTF-8 byte order agree, so this is the order the
    /// bundle is checked to be in and the order the table is emitted in.
    private static func compare(
        _ candidate: [Unicode.Scalar], toPrefixOf view: ScalarView, length: Int
    ) -> Order {
        for offset in 0..<length {
            guard let scalar = view[offset] else { return .after }
            let value = candidate[offset].value
            if value < scalar.value { return .before }
            if value > scalar.value { return .after }
        }
        return .same
    }

    static func asciiCharset(_ view: ScalarView, _ chars: [Unicode.Scalar]) -> Bool {
        view.allSatisfyNonEmpty { chars.contains($0) }
    }
}

extension Predicates {
    /// True when the view is present and holds exactly `length` code points.
    /// An absent view has no length, so it satisfies no length predicate — not
    /// even `length_eq(_, 0)`.
    static func lengthEq(_ view: ScalarView, _ length: Int) -> Bool {
        guard !view.isAbsent else { return false }
        return view.count == length
    }
}
