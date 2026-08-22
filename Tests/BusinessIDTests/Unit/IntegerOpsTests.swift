import Testing

@testable import BusinessID

private func view(_ text: String) -> ScalarView { ScalarView(Array(text.unicodeScalars)) }

/// The expected values here are arithmetic, computed independently of this
/// package. None of them is an identifier: the corpus carries the real ones,
/// published by their issuers.
@Suite("Integer operations")
struct IntegerOpsTests {
    @Test("digits_to_integer reads a decimal view")
    func digitsToInteger() {
        #expect(IntegerOps.digitsToInteger(view("012345674")) == 12_345_674)
        #expect(IntegerOps.digitsToInteger(view("0")) == 0)
        #expect(IntegerOps.digitsToInteger(view("999999999999999999")) == 999_999_999_999_999_999)
    }

    @Test("digits_to_integer is indeterminate on absence, emptiness or a non digit")
    func digitsToIntegerIndeterminate() {
        #expect(IntegerOps.digitsToInteger(.absent) == nil)
        #expect(IntegerOps.digitsToInteger(view("")) == nil)
        #expect(IntegerOps.digitsToInteger(view("12A")) == nil)
        #expect(IntegerOps.digitsToInteger(view("1 2")) == nil)
        // Arabic-Indic digits are digits to Unicode and not ASCII digits here.
        #expect(IntegerOps.digitsToInteger(view("\u{0661}\u{0662}")) == nil)
    }

    @Test("An accumulation beyond Int64 is indeterminate rather than a trap")
    func digitsToIntegerOverflow() {
        // The generator refuses a view it cannot prove is at most eighteen code
        // points, so this is unreachable from an accepted ruleset. Swift traps
        // on overflow, so a hostile ruleset that reached it would crash rather
        // than report; it reports.
        #expect(IntegerOps.digitsToInteger(view(String(repeating: "9", count: 30))) == nil)
    }

    @Test("mod_digits computes the remainder digit by digit")
    func modDigits() {
        #expect(IntegerOps.modDigits(view("195"), modulus: 97) == 1)
        // Far beyond Int64, which is why the operation exists.
        #expect(IntegerOps.modDigits(view(String(repeating: "9", count: 40)), modulus: 97) != nil)
        #expect(IntegerOps.modDigits(view("1000"), modulus: 10) == 0)
        #expect(IntegerOps.modDigits(.absent, modulus: 97) == nil)
        #expect(IntegerOps.modDigits(view(""), modulus: 97) == nil)
        #expect(IntegerOps.modDigits(view("1X"), modulus: 97) == nil)
    }

    @Test("LEFT pairs position i with weight i")
    func weightedSumLeft() {
        let weights: [Int64] = [8, 7, 6, 5, 4, 3, 2]
        #expect(
            IntegerOps.weightedSum(
                view("1234567"), weights: weights, alignment: .left, mapping: .digitValue) == 112
        )
        // Only min(len, weights) positions pair.
        #expect(
            IntegerOps.weightedSum(
                view("12345"), weights: weights, alignment: .left, mapping: .digitValue) == 80
        )
    }

    @Test("RIGHT pairs the last position with the last weight")
    func weightedSumRight() {
        let weights: [Int64] = [8, 7, 6, 5, 4, 3, 2]
        #expect(
            IntegerOps.weightedSum(
                view("1234567"), weights: weights, alignment: .right, mapping: .digitValue) == 112
        )
        #expect(
            IntegerOps.weightedSum(
                view("12345"), weights: weights, alignment: .right, mapping: .digitValue) == 50
        )
    }

    @Test("CYCLE pairs position i with weight i modulo the count")
    func weightedSumCycle() {
        #expect(
            IntegerOps.weightedSum(
                view("1234567"), weights: [1, 2, 3], alignment: .cycle, mapping: .digitValue) == 53
        )
    }

    /// A code point outside the mapping domain makes the sum indeterminate
    /// **anywhere in the view, even at a position no weight pairs with**.
    @Test("An unmapped code point outside the paired range still makes the sum indeterminate")
    func unpairedUnmappedCodePoint() {
        let weights: [Int64] = [1, 1]
        // Positions 0 and 1 pair; the 'A' at position 2 does not, and still
        // decides the answer.
        #expect(
            IntegerOps.weightedSum(
                view("12A"), weights: weights, alignment: .left, mapping: .digitValue) == nil
        )
        #expect(
            IntegerOps.weightedSum(
                view("A12"), weights: weights, alignment: .right, mapping: .digitValue) == nil
        )
    }

    @Test("A custom alphabet values a code point by its index, not by base 36")
    func customAlphabet() {
        // The Chinese unified social credit code omits I, O, S, V and Z, so its
        // J is 18 where base 36 makes it 19.
        let alphabet = Array("0123456789ABCDEFGHJKLMNPQRTUWXY".unicodeScalars)
        #expect(
            IntegerOps.weightedSum(
                view("J"), weights: [1], alignment: .left, mapping: .customAlphabet(alphabet)) == 18
        )
        #expect(
            IntegerOps.weightedSum(
                view("J"), weights: [1], alignment: .left, mapping: .alnumBase36) == 19
        )
        // A code point absent from the alphabet makes the sum indeterminate,
        // exactly as a letter does under DIGIT_VALUE.
        #expect(
            IntegerOps.weightedSum(
                view("I"), weights: [1], alignment: .left, mapping: .customAlphabet(alphabet)) == nil
        )
    }

    @Test("modulo is euclidean and always lands in range")
    func modulo() {
        #expect(IntegerOps.modulo(100, modulus: 97) == 3)
        #expect(IntegerOps.modulo(-1, modulus: 97) == 96)
        #expect(IntegerOps.modulo(0, modulus: 97) == 0)
        #expect(IntegerOps.modulo(nil, modulus: 97) == nil)
    }

    @Test("complement is indeterminate outside the closed range")
    func complement() {
        #expect(IntegerOps.complement(3, modulus: 97) == 94)
        #expect(IntegerOps.complement(0, modulus: 97) == 97)
        #expect(IntegerOps.complement(97, modulus: 97) == 0)
        #expect(IntegerOps.complement(98, modulus: 97) == nil)
        #expect(IntegerOps.complement(-1, modulus: 97) == nil)
        #expect(IntegerOps.complement(nil, modulus: 97) == nil)
    }

    @Test("remainder_map is indeterminate outside the table")
    func remainderMap() {
        let table: [Int64] = [3, 1, 4, 1, 5]
        #expect(IntegerOps.remainderMap(0, values: table) == 3)
        #expect(IntegerOps.remainderMap(4, values: table) == 5)
        #expect(IntegerOps.remainderMap(5, values: table) == nil)
        #expect(IntegerOps.remainderMap(-1, values: table) == nil)
        #expect(IntegerOps.remainderMap(nil, values: table) == nil)
    }

    @Test("An indeterminate integer propagates through every operation")
    func propagation() {
        let indeterminate = IntegerOps.digitsToInteger(.absent)
        #expect(indeterminate == nil)
        #expect(IntegerOps.modulo(indeterminate, modulus: 97) == nil)
        #expect(IntegerOps.complement(indeterminate, modulus: 97) == nil)
        #expect(IntegerOps.remainderMap(indeterminate, values: [1]) == nil)
    }
}
