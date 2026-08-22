/// The checksum operations.
///
/// Every one of them answers `unsupported` where it cannot conclude, and
/// `invalid` only where a documented algorithm ran to completion and disagreed.
enum ChecksumOps {
    /// The Luhn algorithm, whose rightmost digit is the check digit. Valid when
    /// the weighted sum is a multiple of ten. Indeterminate — hence
    /// `unsupported` — when the view is absent, shorter than two code points,
    /// or holds a non ASCII digit.
    static func luhn(_ view: ScalarView, messageKey: String?) -> ChecksumOutcome {
        guard let scalars = view.scalars, scalars.count >= 2 else { return .unsupportedChecksum }
        var total: Int64 = 0
        var doubling = false
        for scalar in scalars.reversed() {
            guard var digit = ASCIIClass.digitValue(scalar) else { return .unsupportedChecksum }
            if doubling {
                digit *= 2
                if digit > 9 { digit -= 9 }
            }
            total += digit
            doubling.toggle()
        }
        return total % 10 == 0 ? .valid : .invalid(messageKey)
    }

    /// ISO 7064 modulo 97-10. Every ASCII letter expands to its base 36 decimal
    /// value and every ASCII digit to itself; the resulting decimal string must
    /// be congruent to one modulo 97.
    ///
    /// The expansion is never materialized: a letter contributes its two
    /// decimal digits directly, which is the same arithmetic without building a
    /// string an attacker would choose the length of.
    static func iso7064Mod97Dash10(_ view: ScalarView, messageKey: String?) -> ChecksumOutcome {
        guard let scalars = view.scalars, scalars.count >= 3 else { return .unsupportedChecksum }
        var remainder: Int64 = 0
        for scalar in scalars {
            if let digit = ASCIIClass.digitValue(scalar) {
                remainder = (remainder * 10 + digit) % 97
            } else if let value = ASCIIClass.base36Value(scalar) {
                // Two decimal digits: 10 through 35.
                remainder = (remainder * 10 + value / 10) % 97
                remainder = (remainder * 10 + value % 10) % 97
            } else {
                return .unsupportedChecksum
            }
        }
        return remainder == 1 ? .valid : .invalid(messageKey)
    }

    /// Compares a computed integer to the ASCII digit at a code point position.
    static func compareDigit(
        _ value: IntegerValue,
        _ view: ScalarView,
        index: Int,
        messageKey: String?
    ) -> ChecksumOutcome {
        guard let value, let scalar = view[index], let digit = ASCIIClass.digitValue(scalar) else {
            return .unsupportedChecksum
        }
        return value == digit ? .valid : .invalid(messageKey)
    }

    /// Compares a computed integer to the decimal value of a slice.
    static func compareSlice(
        _ value: IntegerValue,
        _ view: ScalarView,
        start: Int,
        end: Int,
        messageKey: String?
    ) -> ChecksumOutcome {
        guard let value, let expected = IntegerOps.digitsToInteger(view.slice(start: start, end: end))
        else { return .unsupportedChecksum }
        return value == expected ? .valid : .invalid(messageKey)
    }

    /// Compares a computed integer to a literal constant.
    ///
    /// `compareDigit` and `compareSlice` can only compare against part of the
    /// value being checked, so a rule stating that a remainder must equal a
    /// fixed number had nothing to compare with.
    static func compareConstant(
        _ value: IntegerValue,
        _ constant: Int64,
        messageKey: String?
    ) -> ChecksumOutcome {
        guard let value else { return .unsupportedChecksum }
        return value == constant ? .valid : .invalid(messageKey)
    }

    /// Evaluates operands in order, returning the first `invalid`, otherwise
    /// the first `unsupported`, otherwise `valid`. Every operand is evaluated.
    static func allChecks(_ outcomes: [ChecksumOutcome]) -> ChecksumOutcome {
        var firstUnsupported: ChecksumOutcome?
        for outcome in outcomes {
            switch outcome {
            case .invalid: return outcome
            case .unsupported: if firstUnsupported == nil { firstUnsupported = outcome }
            case .valid, .notApplicable: continue
            }
        }
        return firstUnsupported ?? .valid
    }
}

extension ChecksumOps {
    /// Returns the outcome of the first applicable branch. A `WHEN` branch
    /// whose predicate is false is not applicable; any other branch always is.
    /// When no branch applies the result is `unsupported_checksum`.
    static func choose(_ branches: [ChecksumOutcome]) -> ChecksumOutcome {
        for branch in branches where branch != .notApplicable { return branch }
        return .unsupportedChecksum
    }

    /// Returns `valid` as soon as one operand is valid, otherwise the first
    /// `unsupported`, otherwise the first `invalid`.
    static func anyCheck(_ outcomes: [ChecksumOutcome]) -> ChecksumOutcome {
        var firstUnsupported: ChecksumOutcome?
        var firstInvalid: ChecksumOutcome?
        for outcome in outcomes {
            switch outcome {
            case .valid: return .valid
            case .unsupported: if firstUnsupported == nil { firstUnsupported = outcome }
            case .invalid: if firstInvalid == nil { firstInvalid = outcome }
            case .notApplicable: continue
            }
        }
        return firstUnsupported ?? firstInvalid ?? .unsupportedChecksum
    }
}
