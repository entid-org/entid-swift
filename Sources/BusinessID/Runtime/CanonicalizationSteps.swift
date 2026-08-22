/// The canonicalization steps, applied to the value current at the moment the
/// step runs.
///
/// A canonicalization step never truncates, never fails on user input and never
/// consults a locale. An impossibility inside one after the ruleset was
/// accepted would be an engine defect, never an `invalid` verdict — which is
/// why none of these can fail.
enum CanonicalizationSteps {
    static func trimWhitespace(_ value: inout [Unicode.Scalar]) {
        var start = 0
        var end = value.count
        while start < end, Whitespace.contains(value[start]) { start += 1 }
        while end > start, Whitespace.contains(value[end - 1]) { end -= 1 }
        guard start != 0 || end != value.count else { return }
        value = Array(value[start..<end])
    }

    static func removeWhitespace(_ value: inout [Unicode.Scalar]) {
        value.removeAll(where: Whitespace.contains)
    }

    static func uppercaseASCII(_ value: inout [Unicode.Scalar]) {
        for index in value.indices {
            value[index] = ASCIIClass.uppercased(value[index])
        }
    }

    static func removeChars(_ value: inout [Unicode.Scalar], _ set: [Unicode.Scalar]) {
        value.removeAll { set.contains($0) }
    }

    static func replacePrefix(
        _ value: inout [Unicode.Scalar],
        _ text: [Unicode.Scalar],
        _ replacement: [Unicode.Scalar]
    ) {
        guard value.count >= text.count, value.prefix(text.count).elementsEqual(text) else { return }
        value.replaceSubrange(0..<text.count, with: replacement)
    }

    static func prepend(_ value: inout [Unicode.Scalar], _ text: [Unicode.Scalar]) {
        value.insert(contentsOf: text, at: 0)
    }

    static func append(_ value: inout [Unicode.Scalar], _ text: [Unicode.Scalar]) {
        value.append(contentsOf: text)
    }

    /// Inserts at a code point position. When the index is greater than the
    /// current length the step leaves the value unchanged.
    static func insert(_ value: inout [Unicode.Scalar], at index: Int, _ text: [Unicode.Scalar]) {
        guard index <= value.count else { return }
        value.insert(contentsOf: text, at: index)
    }

    /// Prepends copies of one code point until the value holds `length` of
    /// them. A longer value is never truncated.
    static func leftPad(_ value: inout [Unicode.Scalar], to length: Int, with pad: Unicode.Scalar) {
        guard value.count < length else { return }
        value.insert(contentsOf: repeatElement(pad, count: length - value.count), at: 0)
    }

    /// Leaves the value unchanged when it starts with one of the accepted
    /// prefixes of the selected target; otherwise prepends the canonical prefix
    /// of the target, or its country code when it declares no canonical prefix.
    static func prependCountryIfMissing(
        _ value: inout [Unicode.Scalar],
        acceptedPrefixes: [[Unicode.Scalar]],
        canonicalPrefix: [Unicode.Scalar]
    ) {
        for prefix in acceptedPrefixes
        where value.count >= prefix.count && value.prefix(prefix.count).elementsEqual(prefix) {
            return
        }
        value.insert(contentsOf: canonicalPrefix, at: 0)
    }
}
