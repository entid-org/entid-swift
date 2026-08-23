import Testing

@testable import BusinessID

private func view(_ text: String) -> ScalarView { ScalarView(Array(text.unicodeScalars)) }

/// Arithmetic vectors, computed independently of this package. None of them is
/// an identifier.
@Suite("Checksum operations")
struct ChecksumOpsTests {
    @Test("Luhn accepts a weighted sum that is a multiple of ten")
    func luhnValid() {
        // "18": 8 unchanged, 1 doubled to 2, sum 10.
        #expect(ChecksumOps.luhn(view("18"), messageKey: nil) == .valid)
        #expect(ChecksumOps.luhn(view("26"), messageKey: nil) == .valid)
        #expect(ChecksumOps.luhn(view("00"), messageKey: nil) == .valid)
        #expect(ChecksumOps.luhn(view("1230"), messageKey: nil) == .valid)
    }

    /// The reduction of a doubled digit, on the only digit that exercises it.
    ///
    /// `digit -= 9` fires when doubling overflows nine, and doubling reaches
    /// exactly ten for one digit and no other: five. Every value above used a
    /// doubled digit of four or less, so the comparison could have been written
    /// `> 10` and nothing would have noticed. The whole corpus notices, but the
    /// corpus is the runner's to execute, not this suite's, and a primitive
    /// should not need six hundred cases to pin one subtraction.
    @Test("Luhn reduces a doubled five, which is the only digit that reaches ten")
    func luhnReducesADoubledFive() {
        // "59": 9 unchanged, 5 doubled to 10 and reduced to 1, sum 10.
        // Without the reduction the sum is 19, and the answer flips.
        #expect(ChecksumOps.luhn(view("59"), messageKey: nil) == .valid)
        // "50": 0 unchanged, 5 doubled and reduced to 1, sum 1.
        // Without the reduction the sum is 10, and the answer flips the other
        // way — so both directions are pinned, not just one.
        #expect(ChecksumOps.luhn(view("50"), messageKey: "k") == .invalid("k"))
    }

    @Test("Luhn rejects with invalid_checksum and carries the declared key")
    func luhnInvalid() {
        #expect(ChecksumOps.luhn(view("19"), messageKey: "k") == .invalid("k"))
        #expect(ChecksumOps.luhn(view("1231"), messageKey: nil) == .invalid(nil))
    }

    @Test("Luhn is unsupported, never invalid, when it cannot conclude")
    func luhnIndeterminate() {
        #expect(ChecksumOps.luhn(.absent, messageKey: "k") == .unsupported(.unsupportedChecksum, nil))
        #expect(ChecksumOps.luhn(view("1"), messageKey: nil) == .unsupported(.unsupportedChecksum, nil))
        #expect(ChecksumOps.luhn(view(""), messageKey: nil) == .unsupported(.unsupportedChecksum, nil))
        #expect(ChecksumOps.luhn(view("1A"), messageKey: nil) == .unsupported(.unsupportedChecksum, nil))
    }

    @Test("ISO 7064 mod 97-10 requires a remainder of one")
    func mod97() {
        #expect(ChecksumOps.iso7064Mod97Dash10(view("195"), messageKey: nil) == .valid)
        #expect(ChecksumOps.iso7064Mod97Dash10(view("196"), messageKey: "k") == .invalid("k"))
    }

    @Test("A letter expands to its two base 36 decimal digits")
    func mod97Letters() {
        // "A68" expands to "1068", which is 1 modulo 97.
        #expect(ChecksumOps.iso7064Mod97Dash10(view("A68"), messageKey: nil) == .valid)
        #expect(ChecksumOps.iso7064Mod97Dash10(view("Z90"), messageKey: nil) == .valid)
        #expect(ChecksumOps.iso7064Mod97Dash10(view("A85"), messageKey: nil) == .invalid(nil))
    }

    @Test("ISO 7064 is unsupported below three code points or outside its domain")
    func mod97Indeterminate() {
        let unsupported = ChecksumOutcome.unsupported(.unsupportedChecksum, nil)
        #expect(ChecksumOps.iso7064Mod97Dash10(view("98"), messageKey: nil) == unsupported)
        #expect(ChecksumOps.iso7064Mod97Dash10(.absent, messageKey: nil) == unsupported)
        #expect(ChecksumOps.iso7064Mod97Dash10(view("a95"), messageKey: nil) == unsupported)
        #expect(ChecksumOps.iso7064Mod97Dash10(view("1-5"), messageKey: nil) == unsupported)
    }

    @Test("compare_digit reads one code point position")
    func compareDigit() {
        let value = view("012345674")
        #expect(ChecksumOps.compareDigit(4, value, index: 8, messageKey: nil) == .valid)
        #expect(ChecksumOps.compareDigit(5, value, index: 8, messageKey: "k") == .invalid("k"))
        // Out of range, not a digit, or an indeterminate integer: unsupported.
        let unsupported = ChecksumOutcome.unsupported(.unsupportedChecksum, nil)
        #expect(ChecksumOps.compareDigit(4, value, index: 99, messageKey: nil) == unsupported)
        #expect(ChecksumOps.compareDigit(nil, value, index: 8, messageKey: nil) == unsupported)
        #expect(ChecksumOps.compareDigit(4, view("01234567X"), index: 8, messageKey: nil) == unsupported)
    }

    @Test("compare_slice reads a decimal range")
    func compareSlice() {
        let value = view("FR09012345674")
        #expect(ChecksumOps.compareSlice(9, value, start: 2, end: 4, messageKey: nil) == .valid)
        #expect(ChecksumOps.compareSlice(10, value, start: 2, end: 4, messageKey: "k") == .invalid("k"))
        let unsupported = ChecksumOutcome.unsupported(.unsupportedChecksum, nil)
        #expect(ChecksumOps.compareSlice(9, value, start: 0, end: 2, messageKey: nil) == unsupported)
        #expect(ChecksumOps.compareSlice(9, value, start: 2, end: 99, messageKey: nil) == unsupported)
        #expect(ChecksumOps.compareSlice(nil, value, start: 2, end: 4, messageKey: nil) == unsupported)
    }

    @Test("compare_constant compares against a literal")
    func compareConstant() {
        #expect(ChecksumOps.compareConstant(0, 0, messageKey: nil) == .valid)
        #expect(ChecksumOps.compareConstant(1, 0, messageKey: "k") == .invalid("k"))
        #expect(
            ChecksumOps.compareConstant(nil, 0, messageKey: "k")
                == .unsupported(.unsupportedChecksum, nil)
        )
    }

    @Test("choose returns the first applicable branch")
    func choose() {
        #expect(ChecksumOps.choose([.notApplicable, .valid, .invalid(nil)]) == .valid)
        #expect(ChecksumOps.choose([.invalid("k"), .valid]) == .invalid("k"))
    }

    @Test("choose with no applicable branch is unsupported, never invalid")
    func chooseExhausted() {
        #expect(ChecksumOps.choose([]) == .unsupported(.unsupportedChecksum, nil))
        #expect(
            ChecksumOps.choose([.notApplicable, .notApplicable]) == .unsupported(.unsupportedChecksum, nil)
        )
    }

    @Test("all_checks returns the first invalid, then the first unsupported, then valid")
    func allChecks() {
        let unsupported = ChecksumOutcome.unsupported(.checksumNotPublished, "u")
        #expect(ChecksumOps.allChecks([.valid, .valid]) == .valid)
        #expect(ChecksumOps.allChecks([.valid, unsupported, .valid]) == unsupported)
        #expect(ChecksumOps.allChecks([unsupported, .invalid("i"), .valid]) == .invalid("i"))
        #expect(ChecksumOps.allChecks([]) == .valid)
    }

    @Test("any_check returns valid first, then the first unsupported, then the first invalid")
    func anyCheck() {
        let unsupported = ChecksumOutcome.unsupported(.checksumNotPublished, "u")
        #expect(ChecksumOps.anyCheck([.invalid("i"), .valid]) == .valid)
        #expect(ChecksumOps.anyCheck([.invalid("i"), unsupported]) == unsupported)
        #expect(ChecksumOps.anyCheck([.invalid("i"), .invalid("j")]) == .invalid("i"))
        #expect(ChecksumOps.anyCheck([]) == .unsupported(.unsupportedChecksum, nil))
    }

    /// The most serious defect this project recognises is refusing a valid
    /// identifier, and every path that cannot conclude has to land on
    /// `unsupported`.
    @Test("No operation turns an inability to conclude into invalid")
    func inabilityIsNeverInvalid() {
        let cannotConclude: [ChecksumOutcome] = [
            ChecksumOps.luhn(.absent, messageKey: "k"),
            ChecksumOps.iso7064Mod97Dash10(.absent, messageKey: "k"),
            ChecksumOps.compareDigit(nil, .absent, index: 0, messageKey: "k"),
            ChecksumOps.compareSlice(nil, .absent, start: 0, end: 1, messageKey: "k"),
            ChecksumOps.compareConstant(nil, 0, messageKey: "k"),
            ChecksumOps.choose([.notApplicable]),
            ChecksumOps.anyCheck([]),
        ]
        for outcome in cannotConclude {
            if case .invalid = outcome { Issue.record("an indeterminate result became invalid") }
        }
    }
}
