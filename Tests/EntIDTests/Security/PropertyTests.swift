import Testing

@testable import EntID

/// A small deterministic generator.
///
/// Seeded and reproducible on purpose: a property test that fails only
/// sometimes is a property test nobody fixes.
struct Rng {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407 }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }

    mutating func element<T>(_ values: [T]) -> T { values[int(0...(values.count - 1))] }
}

@Suite("Properties")
struct PropertyTests {
    let engine = EntIDEngine.default

    static let kinds: [IdentifierKind] = [
        "siren", "siret", "vat", "lei", "euid", "cnpj", "uscc", "ein", "duns", "no_such_kind",
    ]

    /// Code points chosen to reach the awkward parts: the frozen whitespace
    /// table, combining marks, an astral plane scalar, right-to-left marks and
    /// the separators canonicalization removes.
    static let alphabet: [Unicode.Scalar] =
        Array(
            "0123456789ABCDEFabcdef -./_".unicodeScalars
        ) + ["\u{00A0}", "\u{FEFF}", "\u{3000}", "\u{0301}", "\u{200B}", "\u{202F}", "\u{200F}", "\u{1F600}"]

    private func randomValue(_ rng: inout Rng) -> String {
        var scalars = String.UnicodeScalarView()
        for _ in 0..<rng.int(0...40) { scalars.append(rng.element(Self.alphabet)) }
        return String(scalars)
    }

    @Test("No user string produces an exception or a trap")
    func neverTraps() {
        var rng = Rng(seed: 0x5EED)
        for _ in 0..<4000 {
            let input = IdentifierInput(
                kind: rng.element(Self.kinds),
                value: randomValue(&rng),
                countryCode: rng.int(0...3) == 0 ? randomValue(&rng) : nil
            )
            _ = engine.canonicalize(input)
            _ = engine.validate(input)
            _ = engine.validateFormat(input)
            _ = engine.validateChecksum(input)
        }
    }

    @Test("Canonicalization is idempotent")
    func idempotent() {
        var rng = Rng(seed: 0xDE_0001)
        for _ in 0..<3000 {
            let kind = rng.element(Self.kinds)
            let first = engine.canonicalize(IdentifierInput(kind: kind, value: randomValue(&rng)))
            guard first.status == .valid else { continue }
            let second = engine.canonicalize(
                IdentifierInput(kind: kind, value: first.canonicalValue)
            )
            #expect(
                second.canonicalValue == first.canonicalValue,
                Comment(rawValue: first.inputValue.debugDescription)
            )
        }
    }

    /// Where a definition removes a separator, it removes it everywhere.
    ///
    /// The rules decide which separators a kind accepts, so the test does not
    /// assume: it asks the engine once, at one position, and then requires the
    /// same answer at every other position. A canonicalizer that stripped a
    /// separator only at the start — or only outside a prefix it recognises —
    /// would pass a fixed example and fail here.
    @Test("A separator a definition removes is removed at every position")
    func separatorRemovalIsPositionIndependent() {
        var rng = Rng(seed: 0x5E9A)
        let separators = [" ", "-", ".", "/", "\u{00A0}"]

        for _ in 0..<1500 {
            let kind = rng.element(Self.kinds)
            let digits = (0..<rng.int(6...12)).map { _ in String(rng.int(0...9)) }.joined()
            let base = engine.canonicalize(IdentifierInput(kind: kind, value: digits))
            guard base.status == .valid else { continue }
            let separator = rng.element(separators)

            // Ask the rules whether this kind removes this separator at all.
            let probe = engine.canonicalize(
                IdentifierInput(kind: kind, value: String(digits.prefix(1)) + separator + digits.dropFirst())
            )
            guard probe.status == .valid, probe.canonicalValue == base.canonicalValue else { continue }

            // It does. Then every other position must agree.
            for cut in 1..<digits.count {
                let index = digits.index(digits.startIndex, offsetBy: cut)
                let decorated = String(digits[..<index]) + separator + String(digits[index...])
                let result = engine.canonicalize(IdentifierInput(kind: kind, value: decorated))
                #expect(
                    result.canonicalValue == base.canonicalValue,
                    Comment(rawValue: "\(kind.rawValue) \(decorated.debugDescription)")
                )
            }
        }
    }

    @Test("An unsupported checksum never becomes invalid")
    func unsupportedNeverBecomesInvalid() {
        var rng = Rng(seed: 0xC0FFEE)
        for _ in 0..<3000 {
            let report = engine.validate(
                IdentifierInput(kind: rng.element(Self.kinds), value: randomValue(&rng))
            )
            if report.checksum.status == .unsupported {
                #expect(report.checksum.reasonCode != .invalidChecksum)
            }
            // Only a reason that proves an invalidity may carry `invalid`.
            if report.format.status == .invalid {
                #expect(
                    [.empty, .invalidLength, .invalidCharacters, .invalidFormat, .countryMismatch]
                        .contains(report.format.reasonCode)
                )
            }
            if report.checksum.status == .invalid {
                #expect(report.checksum.reasonCode == .invalidChecksum)
            }
        }
    }

    @Test("Every status and reason pair the engine emits is one the registry allows")
    func statusReasonPairsAreLegal() {
        var rng = Rng(seed: 0xA11CE)
        for _ in 0..<4000 {
            let report = engine.validate(
                IdentifierInput(
                    kind: rng.element(Self.kinds),
                    value: randomValue(&rng),
                    countryCode: rng.int(0...2) == 0 ? randomValue(&rng) : nil
                )
            )
            for step in [report.format, report.checksum] {
                switch step.status {
                case .valid:
                    #expect(step.reasonCode == .ok)
                case .notRun:
                    #expect(
                        [.notRequested, .notRunFormatInvalid, .notRunFormatUnsupported]
                            .contains(step.reasonCode)
                    )
                case .invalid:
                    #expect(
                        [
                            .empty, .invalidLength, .invalidCharacters, .invalidFormat, .invalidChecksum,
                            .countryMismatch,
                        ].contains(step.reasonCode)
                    )
                case .unsupported:
                    #expect(step.reasonCode != .ok)
                }
            }
        }
    }

    @Test("A checksum is never reported as run when the format did not validate")
    func checksumFollowsFormat() {
        var rng = Rng(seed: 0xBEEF)
        for _ in 0..<3000 {
            let report = engine.validate(
                IdentifierInput(kind: rng.element(Self.kinds), value: randomValue(&rng))
            )
            switch report.format.status {
            case .invalid:
                #expect(report.checksum.status == .notRun)
                #expect(report.checksum.reasonCode == .notRunFormatInvalid)
            case .unsupported:
                #expect(report.checksum.status == .notRun)
                #expect(report.checksum.reasonCode == .notRunFormatUnsupported)
            case .valid:
                #expect(report.checksum.status != .notRun)
            case .notRun:
                Issue.record("format is never not_run")
            }
        }
    }

    @Test("The raw input always survives unchanged into the report")
    func inputSurvives() {
        var rng = Rng(seed: 0xD00D)
        for _ in 0..<2000 {
            let value = randomValue(&rng)
            let input = IdentifierInput(kind: rng.element(Self.kinds), value: value)
            #expect(engine.validate(input).inputValue == value)
            #expect(engine.canonicalize(input).inputValue == value)
        }
    }

    @Test("Mutating a check digit invalidates where the algorithm guarantees it")
    func mutatedCheckDigit() {
        // `siren-validate-format-050` carries a Luhn check digit, so changing
        // the last digit must break the checksum for nine of the ten values.
        let base = "012345674"
        var broken = 0
        for digit in 0...9 {
            let candidate = String(base.dropLast()) + String(digit)
            let report = engine.validate(IdentifierInput(kind: "siren", value: candidate))
            #expect(report.format.status == .valid, Comment(rawValue: candidate))
            if report.checksum.status == .invalid { broken += 1 }
        }
        #expect(broken == 9)
    }
}
