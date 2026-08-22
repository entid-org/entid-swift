import Testing

@testable import BusinessID

private func scalars(_ text: String) -> [Unicode.Scalar] { Array(text.unicodeScalars) }
private func text(_ value: [Unicode.Scalar]) -> String { String(String.UnicodeScalarView(value)) }

@Suite("Canonicalization steps")
struct CanonicalizationTests {
    @Test("Trim removes the frozen table from both ends and nothing inside")
    func trim() {
        var value = scalars("\u{FEFF} \u{3000}FR 09\u{00A0}\t")
        CanonicalizationSteps.trimWhitespace(&value)
        #expect(text(value) == "FR 09")
    }

    @Test("Trim on a value made only of whitespace yields the empty value")
    func trimEverything() {
        var value = scalars(" \t\u{2028}\u{FEFF}")
        CanonicalizationSteps.trimWhitespace(&value)
        #expect(value.isEmpty)
    }

    @Test("Remove takes every occurrence of the frozen table")
    func removeWhitespace() {
        var value = scalars("F R\u{00A0}0\u{2003}9")
        CanonicalizationSteps.removeWhitespace(&value)
        #expect(text(value) == "FR09")
    }

    @Test("Uppercase maps only a..z")
    func uppercase() {
        var value = scalars("fr-\u{00E9}\u{0131}9")
        CanonicalizationSteps.uppercaseASCII(&value)
        #expect(text(value) == "FR-\u{00E9}\u{0131}9")
    }

    @Test("Remove chars takes only the declared set")
    func removeChars() {
        var value = scalars("012.345-674")
        CanonicalizationSteps.removeChars(&value, scalars(".-"))
        #expect(text(value) == "012345674")
    }

    @Test("Replace prefix touches only an exact leading match")
    func replacePrefix() {
        var value = scalars("GR012")
        CanonicalizationSteps.replacePrefix(&value, scalars("GR"), scalars("EL"))
        #expect(text(value) == "EL012")

        var untouched = scalars("XGR012")
        CanonicalizationSteps.replacePrefix(&untouched, scalars("GR"), scalars("EL"))
        #expect(text(untouched) == "XGR012")
    }

    @Test("Insert beyond the current length leaves the value unchanged")
    func insertBeyondLength() {
        var value = scalars("ABC")
        CanonicalizationSteps.insert(&value, at: 4, scalars("-"))
        #expect(text(value) == "ABC")

        CanonicalizationSteps.insert(&value, at: 3, scalars("-"))
        #expect(text(value) == "ABC-")

        CanonicalizationSteps.insert(&value, at: 1, scalars("+"))
        #expect(text(value) == "A+BC-")
    }

    @Test("Left pad never truncates a longer value")
    func leftPad() {
        var short = scalars("12")
        CanonicalizationSteps.leftPad(&short, to: 5, with: "0")
        #expect(text(short) == "00012")

        var long = scalars("1234567")
        CanonicalizationSteps.leftPad(&long, to: 5, with: "0")
        #expect(text(long) == "1234567")
    }

    @Test("Prepend country leaves a value already carrying an accepted prefix")
    func prependCountryPresent() {
        var value = scalars("EL012")
        CanonicalizationSteps.prependCountryIfMissing(
            &value, acceptedPrefixes: [scalars("EL"), scalars("GR")], canonicalPrefix: scalars("EL")
        )
        #expect(text(value) == "EL012")
    }

    @Test("Prepend country adds the canonical prefix when none is present")
    func prependCountryMissing() {
        var value = scalars("012")
        CanonicalizationSteps.prependCountryIfMissing(
            &value, acceptedPrefixes: [scalars("EL"), scalars("GR")], canonicalPrefix: scalars("EL")
        )
        #expect(text(value) == "EL012")
    }

    @Test("Each step is idempotent on its own output")
    func idempotence() {
        var value = scalars("  fr 09.12-34  ")
        CanonicalizationSteps.trimWhitespace(&value)
        CanonicalizationSteps.uppercaseASCII(&value)
        CanonicalizationSteps.removeWhitespace(&value)
        CanonicalizationSteps.removeChars(&value, scalars(".-"))
        let once = value

        CanonicalizationSteps.trimWhitespace(&value)
        CanonicalizationSteps.uppercaseASCII(&value)
        CanonicalizationSteps.removeWhitespace(&value)
        CanonicalizationSteps.removeChars(&value, scalars(".-"))
        #expect(value == once)
    }
}
