/// A possibly absent view over a sequence of Unicode code points.
///
/// Positions and lengths are counted in code points, never in grapheme
/// clusters and never in UTF-16 units. `String.count` counts grapheme clusters,
/// which agrees with a code point count on every ASCII identifier and stops
/// agreeing the moment a combining sequence appears — so `String` is never
/// indexed here.
///
/// Absence propagates: every constructor applied to an absent operand yields an
/// absent result, and every predicate applied to one yields `false` except
/// `isAbsent`. Absence is never an error.
struct ScalarView: Sendable {
    private let storage: ArraySlice<Unicode.Scalar>?

    static let absent = ScalarView(storage: nil)

    private init(storage: ArraySlice<Unicode.Scalar>?) { self.storage = storage }

    init(_ scalars: [Unicode.Scalar]) { storage = scalars[...] }
    init(_ scalars: ArraySlice<Unicode.Scalar>) { storage = scalars }

    var isAbsent: Bool { storage == nil }

    /// The number of code points, or zero when absent. Callers that care about
    /// the difference ask `isAbsent` first.
    var count: Int { storage?.count ?? 0 }

    var scalars: ArraySlice<Unicode.Scalar>? { storage }

    subscript(offset: Int) -> Unicode.Scalar? {
        guard let storage, offset >= 0, offset < storage.count else { return nil }
        return storage[storage.startIndex + offset]
    }

    var string: String {
        guard let storage else { return "" }
        var result = String.UnicodeScalarView()
        result.append(contentsOf: storage)
        return String(result)
    }

    // MARK: - Constructors

    /// `[start, end)`. Absent when the operand is absent, when `start > end`,
    /// or when `end` exceeds the length.
    func slice(start: Int, end: Int) -> ScalarView {
        guard let storage, start <= end, end <= storage.count else { return .absent }
        let lower = storage.startIndex + start
        return ScalarView(storage[lower..<(storage.startIndex + end)])
    }

    /// From `start` to the end. Absent when `start` exceeds the length.
    func slice(from start: Int) -> ScalarView {
        guard let storage, start <= storage.count else { return .absent }
        return ScalarView(storage[(storage.startIndex + start)...])
    }

    /// Before `end`. Absent when `end` exceeds the length.
    func slice(to end: Int) -> ScalarView {
        guard let storage, end <= storage.count else { return .absent }
        return ScalarView(storage[..<(storage.startIndex + end)])
    }

    /// The part before the first occurrence of a non empty literal. Absent when
    /// the literal does not occur.
    func before(first literal: [Unicode.Scalar]) -> ScalarView {
        guard let storage, let offset = firstOccurrence(of: literal, in: storage) else { return .absent }
        return ScalarView(storage[..<(storage.startIndex + offset)])
    }

    /// The part after the first occurrence of a non empty literal.
    func after(first literal: [Unicode.Scalar]) -> ScalarView {
        guard let storage, let offset = firstOccurrence(of: literal, in: storage) else { return .absent }
        return ScalarView(storage[(storage.startIndex + offset + literal.count)...])
    }

    /// The view without its exact leading literal. Absent when it does not
    /// start with it.
    func strippingPrefix(_ literal: [Unicode.Scalar]) -> ScalarView {
        guard let storage, hasPrefix(literal) else { return .absent }
        return ScalarView(storage[(storage.startIndex + literal.count)...])
    }

    /// Concatenates in order. Absent when any operand is absent.
    static func concatenating(_ views: [ScalarView]) -> ScalarView {
        var joined: [Unicode.Scalar] = []
        for view in views {
            guard let scalars = view.storage else { return .absent }
            joined.append(contentsOf: scalars)
        }
        return ScalarView(joined)
    }

    // MARK: - Predicates

    /// Present and holding zero code points. False when absent.
    var isEmptyView: Bool { storage?.isEmpty ?? false }

    func hasPrefix(_ literal: [Unicode.Scalar]) -> Bool {
        guard let storage, literal.count <= storage.count else { return false }
        return storage.prefix(literal.count).elementsEqual(literal)
    }

    func hasSuffix(_ literal: [Unicode.Scalar]) -> Bool {
        guard let storage, literal.count <= storage.count else { return false }
        return storage.suffix(literal.count).elementsEqual(literal)
    }

    func contains(_ literal: [Unicode.Scalar]) -> Bool {
        guard let storage else { return false }
        return firstOccurrence(of: literal, in: storage) != nil
    }

    /// Present, non empty, and every code point satisfies the class.
    func allSatisfyNonEmpty(_ predicate: (Unicode.Scalar) -> Bool) -> Bool {
        guard let storage, !storage.isEmpty else { return false }
        return storage.allSatisfy(predicate)
    }

    /// The IR `equals` predicate: true when both operands are present and hold
    /// the same code point sequence, false when either is absent.
    ///
    /// This is deliberately a named method and not `==`. A view is not
    /// `Equatable`, because an absent view equals nothing — not even itself —
    /// and a non reflexive `==` breaks every collection that relies on one.
    func matches(_ other: ScalarView) -> Bool {
        guard let left = storage, let right = other.storage else { return false }
        return left.elementsEqual(right)
    }

    // MARK: - Search

    private func firstOccurrence(
        of literal: [Unicode.Scalar],
        in scalars: ArraySlice<Unicode.Scalar>
    ) -> Int? {
        guard !literal.isEmpty, literal.count <= scalars.count else { return nil }
        let last = scalars.count - literal.count
        var offset = 0
        while offset <= last {
            let lower = scalars.startIndex + offset
            if scalars[lower..<(lower + literal.count)].elementsEqual(literal) { return offset }
            offset += 1
        }
        return nil
    }
}

/// Prefix matching over a bare code point buffer, which dispatch does before
/// any view exists.
enum PrefixMatch {
    static func hasPrefix(_ value: [Unicode.Scalar], _ literal: [Unicode.Scalar]) -> Bool {
        guard literal.count <= value.count else { return false }
        return value.prefix(literal.count).elementsEqual(literal)
    }
}
