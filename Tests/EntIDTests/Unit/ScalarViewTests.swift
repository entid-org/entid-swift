import Testing

@testable import EntID

private func view(_ text: String) -> ScalarView { ScalarView(Array(text.unicodeScalars)) }
private func literal(_ text: String) -> [Unicode.Scalar] { Array(text.unicodeScalars) }

@Suite("String views")
struct ScalarViewTests {
    @Test("Positions are code points, not grapheme clusters")
    func codePointPositions() {
        // "e" followed by a combining acute is two code points and one
        // grapheme cluster. `String.count` would say one.
        let combining = view("e\u{0301}f")
        #expect(combining.count == 3)
        #expect(combining.slice(start: 0, end: 2).string == "e\u{0301}")
        #expect(combining[2] == "f")
    }

    @Test("A slice is absent when start exceeds end")
    func invertedSlice() {
        #expect(view("ABCDEF").slice(start: 4, end: 2).isAbsent)
    }

    @Test("A slice is absent when the end exceeds the length")
    func sliceBeyondEnd() {
        #expect(view("ABC").slice(start: 0, end: 4).isAbsent)
        #expect(view("ABC").slice(start: 0, end: 3).string == "ABC")
        #expect(view("ABC").slice(to: 4).isAbsent)
        #expect(view("ABC").slice(from: 4).isAbsent)
        // A start exactly at the end yields the empty view, not an absent one.
        #expect(view("ABC").slice(from: 3).isAbsent == false)
        #expect(view("ABC").slice(from: 3).isEmptyView)
    }

    @Test("Absence propagates through every string constructor")
    func absencePropagates() {
        let absent = ScalarView.absent
        #expect(absent.slice(start: 0, end: 0).isAbsent)
        #expect(absent.slice(from: 0).isAbsent)
        #expect(absent.slice(to: 0).isAbsent)
        #expect(absent.before(first: literal("-")).isAbsent)
        #expect(absent.after(first: literal("-")).isAbsent)
        #expect(absent.strippingPrefix(literal("A")).isAbsent)
        #expect(ScalarView.concatenating([view("A"), absent]).isAbsent)
    }

    @Test("Every predicate on an absent view is false, except isAbsent")
    func predicatesOnAbsence() {
        let absent = ScalarView.absent
        #expect(absent.isAbsent)
        #expect(!absent.isEmptyView)
        #expect(!absent.hasPrefix(literal("A")))
        #expect(!absent.hasSuffix(literal("A")))
        #expect(!absent.contains(literal("A")))
        #expect(!absent.matches(absent))
        #expect(!absent.matches(view("")))
        #expect(!absent.allSatisfyNonEmpty(ASCIIClass.isDigit))
        #expect(!Predicates.lengthEq(absent, 0))
        #expect(!Predicates.lengthIn(absent, [0]))
        #expect(!Predicates.lengthBetween(absent, 0, 9))
        #expect(!Predicates.charAtIn(absent, 0, literal("A")))
        #expect(!Predicates.prefixIn(absent, [literal("A")]))
        #expect(!Predicates.asciiCharset(absent, literal("A")))
    }

    @Test("An empty view is present and satisfies isEmpty")
    func emptyIsNotAbsent() {
        let empty = view("")
        #expect(!empty.isAbsent)
        #expect(empty.isEmptyView)
        #expect(empty.matches(view("")))
        // An ASCII class needs at least one code point.
        #expect(!empty.allSatisfyNonEmpty(ASCIIClass.isDigit))
    }

    @Test("before and after split on the first occurrence only")
    func firstOccurrence() {
        let value = view("FR.TVX.012")
        #expect(value.before(first: literal(".")).string == "FR")
        #expect(value.after(first: literal(".")).string == "TVX.012")
        #expect(value.before(first: literal("/")).isAbsent)
        #expect(value.after(first: literal("/")).isAbsent)
    }

    @Test("Stripping a prefix the view does not carry yields absence")
    func stripPrefix() {
        #expect(view("BE0123").strippingPrefix(literal("BE")).string == "0123")
        #expect(view("BE0123").strippingPrefix(literal("FR")).isAbsent)
    }

    @Test("Concatenation keeps operand order")
    func concatenation() {
        #expect(ScalarView.concatenating([view("FR"), view("09"), view("12")]).string == "FR0912")
        #expect(ScalarView.concatenating([]).string.isEmpty)
    }

    @Test("A view slices its own coordinates, not the base array's")
    func nestedSlices() {
        let outer = view("XXABCDEYY").slice(start: 2, end: 7)
        #expect(outer.string == "ABCDE")
        #expect(outer.slice(start: 1, end: 3).string == "BC")
        #expect(outer[0] == "A")
        #expect(outer.slice(start: 0, end: 6).isAbsent)

        // The position one past the end is not a position. On a sub-slice the
        // element is still there in the base array, and returning it would read
        // outside the view while trapping nowhere.
        #expect(outer[5] == nil)
        #expect(outer[4] == "E")
        #expect(!Predicates.charAtIn(outer, 5, literal("Y")))
        #expect(Predicates.charAtIn(outer, 4, literal("E")))
    }
}

@Suite("Frozen character tables")
struct CharacterTableTests {
    @Test("The whitespace_v1 table holds exactly its declared code points")
    func whitespaceTable() {
        let declared: Set<UInt32> = Set(
            Array(0x0009...0x000D) + [0x0020, 0x0085, 0x00A0, 0x1680]
                + Array(0x2000...0x200A) + [0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF]
        )
        for value in UInt32(0)...0xFFFF {
            guard let scalar = Unicode.Scalar(value) else { continue }
            #expect(
                Whitespace.contains(scalar) == declared.contains(value),
                "U+\(String(value, radix: 16, uppercase: true))"
            )
        }
    }

    /// The table is not what a Unicode runtime calls whitespace, and that is the
    /// point: `U+180E` and `U+200B` are excluded here, and platform tables have
    /// disagreed about both across versions.
    @Test("The table is not delegated to the platform's own idea of whitespace")
    func tableIsNotDelegated() {
        #expect(!Whitespace.contains("\u{180E}"))
        #expect(!Whitespace.contains("\u{200B}"))
        #expect(Whitespace.contains("\u{FEFF}"))
        #expect(Whitespace.contains("\u{00A0}"))
    }

    @Test("Dispatch trims only the seven ASCII code points")
    func asciiTrimTable() {
        for value in UInt32(0)...0x3000 {
            guard let scalar = Unicode.Scalar(value) else { continue }
            let expected = (0x09...0x0D).contains(value) || value == 0x20
            #expect(Whitespace.isASCIITrimmable(scalar) == expected)
        }
    }

    @Test("uppercase_ascii maps only a..z and consults no locale")
    func uppercaseASCII() {
        #expect(ASCIIClass.uppercased("a") == "A")
        #expect(ASCIIClass.uppercased("z") == "Z")
        #expect(ASCIIClass.uppercased("0") == "0")
        // Turkish dotless i, German sharp s and the Kelvin sign are all left
        // alone: a locale aware uppercase would move at least one of them.
        #expect(ASCIIClass.uppercased("\u{0131}") == "\u{0131}")
        #expect(ASCIIClass.uppercased("\u{00DF}") == "\u{00DF}")
        #expect(ASCIIClass.uppercased("\u{212A}") == "\u{212A}")
        #expect(ASCIIClass.uppercased("\u{00E9}") == "\u{00E9}")
    }

    @Test("The ASCII classes are the declared ranges and nothing else")
    func asciiClasses() {
        for value in UInt32(0)...0x2FF {
            guard let scalar = Unicode.Scalar(value) else { continue }
            #expect(ASCIIClass.isDigit(scalar) == (0x30...0x39).contains(value))
            #expect(ASCIIClass.isUpperLetter(scalar) == (0x41...0x5A).contains(value))
            #expect(ASCIIClass.isLowerLetter(scalar) == (0x61...0x7A).contains(value))
        }
        // Arabic-Indic and fullwidth digits are digits to Unicode and are not
        // ASCII digits here.
        #expect(!ASCIIClass.isDigit("\u{0660}"))
        #expect(!ASCIIClass.isDigit("\u{FF10}"))
    }

    @Test("Base 36 covers digits then upper letters")
    func base36() {
        #expect(ASCIIClass.base36Value("0") == 0)
        #expect(ASCIIClass.base36Value("9") == 9)
        #expect(ASCIIClass.base36Value("A") == 10)
        #expect(ASCIIClass.base36Value("Z") == 35)
        #expect(ASCIIClass.base36Value("a") == nil)
        #expect(ASCIIClass.base36Value("-") == nil)
    }
}
