/// How a code point becomes a numeric contribution in a weighted sum.
enum CharMapping: Sendable, Equatable {
    case digitValue
    case alnumBase36
    /// The value of a code point is its index in the issuer's own alphabet.
    /// An issuer's alphabet is often neither base 10 nor base 36: the Chinese
    /// unified social credit code omits I, O, S, V and Z, so its `J` is 18
    /// where base 36 makes it 19.
    case customAlphabet([Unicode.Scalar])

    func value(of scalar: Unicode.Scalar) -> Int64? {
        switch self {
        case .digitValue: ASCIIClass.digitValue(scalar)
        case .alnumBase36: ASCIIClass.base36Value(scalar)
        case .customAlphabet(let alphabet): alphabet.firstIndex(of: scalar).map(Int64.init)
        }
    }
}

/// How weights are paired with input code points.
enum WeightAlignment: Sendable, Equatable {
    /// Position `i` pairs with `weights[i]`.
    case left
    /// The last position pairs with the last weight.
    case right
    /// Position `i` pairs with `weights[i % count]`.
    case cycle
}

/// The integer constructors.
///
/// Every one of them yields `nil` — indeterminate — rather than throwing or
/// trapping. Arbitrarily long numbers are never converted to an integer: the
/// modulo is computed digit by digit.
enum IntegerOps {
    /// Reads the view as a non negative decimal integer. Indeterminate when the
    /// view is absent, empty or holds a non ASCII digit.
    ///
    /// The generator only emits this where it proved the view is at most
    /// eighteen code points, so the accumulation cannot overflow. The checked
    /// arithmetic below is what makes that proof unnecessary to trust.
    static func digitsToInteger(_ view: ScalarView) -> IntegerValue {
        guard let scalars = view.scalars, !scalars.isEmpty else { return nil }
        var total: Int64 = 0
        for scalar in scalars {
            guard let digit = ASCIIClass.digitValue(scalar) else { return nil }
            let (scaled, scaleOverflow) = total.multipliedReportingOverflow(by: 10)
            guard !scaleOverflow else { return nil }
            let (sum, sumOverflow) = scaled.addingReportingOverflow(digit)
            guard !sumOverflow else { return nil }
            total = sum
        }
        return total
    }

    /// The remainder of the view modulo `modulus`, digit by digit, without any
    /// big integer conversion. The result lies in `[0, modulus)`.
    static func modDigits(_ view: ScalarView, modulus: Int64) -> IntegerValue {
        guard let scalars = view.scalars, !scalars.isEmpty else { return nil }
        var remainder: Int64 = 0
        for scalar in scalars {
            guard let digit = ASCIIClass.digitValue(scalar) else { return nil }
            remainder = (remainder * 10 + digit) % modulus
        }
        return remainder
    }

    /// Sums `mapping(expr[i]) * weight(i)` over the paired positions.
    ///
    /// Indeterminate when the view is absent, empty, or holds a code point
    /// outside the mapping domain **anywhere in the view, even at a position no
    /// weight pairs with**. That is why the mapping runs over everything before
    /// any pairing happens.
    static func weightedSum(
        _ view: ScalarView,
        weights: [Int64],
        alignment: WeightAlignment,
        mapping: CharMapping
    ) -> IntegerValue {
        guard let scalars = view.scalars, !scalars.isEmpty, !weights.isEmpty else { return nil }

        var mapped: [Int64] = []
        mapped.reserveCapacity(scalars.count)
        for scalar in scalars {
            guard let value = mapping.value(of: scalar) else { return nil }
            mapped.append(value)
        }

        var total: Int64 = 0
        func accumulate(_ value: Int64, _ weight: Int64) -> Bool {
            let (product, productOverflow) = value.multipliedReportingOverflow(by: weight)
            guard !productOverflow else { return false }
            let (sum, sumOverflow) = total.addingReportingOverflow(product)
            guard !sumOverflow else { return false }
            total = sum
            return true
        }

        switch alignment {
        case .left:
            // Only min(len(expr), len(weights)) positions pair; the remaining
            // positions of the view contribute nothing.
            for index in 0..<min(mapped.count, weights.count) {
                guard accumulate(mapped[index], weights[index]) else { return nil }
            }
        case .right:
            // The last position pairs with the last weight, walking backwards.
            for offset in 0..<min(mapped.count, weights.count) {
                guard accumulate(mapped[mapped.count - 1 - offset], weights[weights.count - 1 - offset])
                else { return nil }
            }
        case .cycle:
            for index in mapped.indices {
                guard accumulate(mapped[index], weights[index % weights.count]) else { return nil }
            }
        }
        return total
    }

    /// Euclidean remainder. The result always lies in `[0, modulus)`.
    static func modulo(_ value: IntegerValue, modulus: Int64) -> IntegerValue {
        guard let value else { return nil }
        let remainder = value % modulus
        return remainder < 0 ? remainder + modulus : remainder
    }

    /// `modulus - value`. Indeterminate when the operand is outside
    /// `[0, modulus]`, which is also what keeps the subtraction in range.
    static func complement(_ value: IntegerValue, modulus: Int64) -> IntegerValue {
        guard let value, value >= 0, value <= modulus else { return nil }
        return modulus - value
    }

    /// `values[index]`. Indeterminate when the index is outside the table.
    static func remainderMap(_ value: IntegerValue, values: [Int64]) -> IntegerValue {
        guard let value, value >= 0, value < Int64(values.count) else { return nil }
        return values[Int(value)]
    }
}
