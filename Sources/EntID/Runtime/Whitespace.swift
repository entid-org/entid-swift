/// The frozen `whitespace_v1` table.
///
/// A runtime must never delegate this definition to its own Unicode tables:
/// their versions differ between platforms and releases, and two engines would
/// then disagree on a canonical value. `Character.isWhitespace` is exactly that
/// delegation, so it appears nowhere in this package.
enum Whitespace {
    static func contains(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0009...0x000D,  // tab, line feed, line tabulation, form feed, carriage return
            0x0020,  // space
            0x0085,  // next line
            0x00A0,  // no-break space
            0x1680,  // ogham space mark
            0x2000...0x200A,  // en quad through hair space
            0x2028,  // line separator
            0x2029,  // paragraph separator
            0x202F,  // narrow no-break space
            0x205F,  // medium mathematical space
            0x3000,  // ideographic space
            0xFEFF:  // zero width no-break space
            true
        default:
            false
        }
    }

    /// The narrower table dispatch trims with: `U+0009..U+000D` and `U+0020`
    /// only, at both ends of a kind or country token.
    static func isASCIITrimmable(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0009...0x000D, 0x0020: true
        default: false
        }
    }
}

/// The V1 character classes, which are ASCII only.
enum ASCIIClass {
    static func isDigit(_ scalar: Unicode.Scalar) -> Bool { (0x30...0x39).contains(scalar.value) }
    static func isUpperLetter(_ scalar: Unicode.Scalar) -> Bool { (0x41...0x5A).contains(scalar.value) }
    static func isLowerLetter(_ scalar: Unicode.Scalar) -> Bool { (0x61...0x7A).contains(scalar.value) }
    static func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        isDigit(scalar) || isUpperLetter(scalar)
    }

    /// The decimal value of an ASCII digit.
    static func digitValue(_ scalar: Unicode.Scalar) -> Int64? {
        isDigit(scalar) ? Int64(scalar.value - 0x30) : nil
    }

    /// The base 36 value of an ASCII digit or upper letter: `0..9` then `10..35`.
    static func base36Value(_ scalar: Unicode.Scalar) -> Int64? {
        if isDigit(scalar) { return Int64(scalar.value - 0x30) }
        if isUpperLetter(scalar) { return Int64(scalar.value - 0x41) + 10 }
        return nil
    }

    /// Maps only `a..z` to `A..Z`, and never consults a locale.
    static func uppercased(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        guard isLowerLetter(scalar), let upper = Unicode.Scalar(scalar.value - 0x20) else {
            return scalar
        }
        return upper
    }
}
