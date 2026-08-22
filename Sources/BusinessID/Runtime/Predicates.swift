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
    static func prefixIn(_ view: ScalarView, _ prefixes: [[Unicode.Scalar]]) -> Bool {
        prefixes.contains { view.hasPrefix($0) }
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
