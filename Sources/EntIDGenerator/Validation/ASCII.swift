/// The ASCII token shapes `ir.md` section 5 states for dispatch.
///
/// None of them consults a locale or a Unicode table: the classes are ASCII
/// ranges, written out.
enum TokenShape {
    /// `[a-z][a-z0-9_-]{0,63}` after trim and lower casing.
    static func isWellFormedKind(_ token: String) -> Bool {
        let scalars = Array(token.unicodeScalars)
        guard (1...64).contains(scalars.count) else { return false }
        guard ("a"..."z").contains(scalars[0]) else { return false }
        return scalars.dropFirst().allSatisfy {
            ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" || $0 == "-"
        }
    }

    /// `[A-Z]{2}` after trim and upper casing.
    static func isWellFormedCountry(_ token: String) -> Bool {
        let scalars = Array(token.unicodeScalars)
        return scalars.count == 2 && scalars.allSatisfy { ("A"..."Z").contains($0) }
    }

    /// One to eight ASCII alphanumeric characters, compared case sensitively.
    static func isWellFormedPrefix(_ token: String) -> Bool {
        let scalars = Array(token.unicodeScalars)
        guard (1...8).contains(scalars.count) else { return false }
        return scalars.allSatisfy {
            ("0"..."9").contains($0) || ("A"..."Z").contains($0) || ("a"..."z").contains($0)
        }
    }

    /// `ir.md` check 6: ASCII letters, digits, dot, dash and underscore.
    static func isWellFormedRulesVersion(_ token: String) -> Bool {
        let bytes = Array(token.utf8)
        guard (1...Limits.maximumRulesVersionBytes).contains(bytes.count) else { return false }
        return bytes.allSatisfy { byte in
            (0x30...0x39).contains(byte)  // 0-9
                || (0x41...0x5A).contains(byte)  // A-Z
                || (0x61...0x7A).contains(byte)  // a-z
                || byte == 0x2E || byte == 0x2D || byte == 0x5F  // . - _
        }
    }

    static func isASCII(_ scalar: Unicode.Scalar) -> Bool { scalar.value < 0x80 }
}

/// Ordering by UTF-8 bytes, which is the order `ir.md` section 9 states for
/// every sorted repeated field. Swift's `<` on `String` compares by Unicode
/// canonical equivalence instead, which is not the same order.
func precedesByUTF8(_ lhs: String, _ rhs: String) -> Bool {
    Array(lhs.utf8).lexicographicallyPrecedes(Array(rhs.utf8))
}
