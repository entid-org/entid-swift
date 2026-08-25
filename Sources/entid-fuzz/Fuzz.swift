import EntID
import EntIDGenerator
import Foundation

/// A deterministic fuzz harness for the two surfaces that read untrusted input:
/// the generator's bundle decoder and the engine's public API.
///
/// Deterministic on purpose. A fuzzer that finds a crash once and cannot
/// reproduce it has found nothing anyone can fix, so every run is driven by a
/// seed printed in the output and accepted on the command line.
///
///     entid-fuzz [--seed N] [--rounds N] [--rules path]
@main
struct Fuzz {
    static func main() {
        var seed: UInt64 = 1
        var rounds = 20000
        var rulesPath = "spec/entid-rules.binpb"

        var arguments = CommandLine.arguments.dropFirst().makeIterator()
        while let argument = arguments.next() {
            switch argument {
            case "--seed": seed = arguments.next().flatMap(UInt64.init) ?? seed
            case "--rounds": rounds = arguments.next().flatMap(Int.init) ?? rounds
            case "--rules": rulesPath = arguments.next() ?? rulesPath
            default: break
            }
        }

        print("entid-fuzz: seed \(seed), \(rounds) rounds")
        var rng = Rng(seed: seed)

        fuzzEngine(&rng, rounds: rounds)
        if let bundle = FileManager.default.contents(atPath: rulesPath) {
            fuzzDecoder(&rng, seed: [UInt8](bundle), rounds: rounds / 10)
        } else {
            print("entid-fuzz: no bundle at \(rulesPath), decoder rounds skipped")
        }
        fuzzDecoderFromNothing(&rng, rounds: rounds / 10)
        print("entid-fuzz: no crash, no hang, no unbounded allocation")
    }

    // MARK: - Engine

    /// Any string a caller can write must produce a report, never an exception,
    /// a trap or an unbounded allocation.
    static func fuzzEngine(_ rng: inout Rng, rounds: Int) {
        let kinds = ["siren", "vat", "lei", "euid", "uscc", "cnpj", "ein", "", "VAT ", "\u{1F600}"]
        let engine = EntIDEngine.default
        var reports = 0

        for round in 0..<rounds {
            let kind = IdentifierKind(kinds[Int(rng.next() % UInt64(kinds.count))])
            let value = rng.string(upTo: round.isMultiple(of: 97) ? 2000 : 48)
            let country = rng.next().isMultiple(of: 4) ? rng.string(upTo: 6) : nil
            let profile: ValidationProfile? =
                switch rng.next() % 3 {
                case 0: nil
                case 1: .compatible
                default: .strictCurrent
                }
            let input = IdentifierInput(kind: kind, value: value, countryCode: country)
            let options = ValidationOptions(profile: profile)

            _ = engine.canonicalize(input, options: options)
            _ = engine.validateFormat(input, options: options)
            let report = engine.validate(input, options: options)
            precondition(report.inputValue == value, "the raw input was modified")
            precondition(
                report.format.status != .notRun, "the format step is never not_run"
            )
            reports += 1
        }
        print("entid-fuzz: \(reports) engine rounds")
    }

    // MARK: - Decoder

    /// Mutations of a valid bundle: the shape a forged artefact takes.
    static func fuzzDecoder(_ rng: inout Rng, seed: [UInt8], rounds: Int) {
        var refused = 0
        var accepted = 0
        for _ in 0..<rounds {
            var bytes = seed
            for _ in 0...(rng.next() % 8) {
                let index = Int(rng.next() % UInt64(bytes.count))
                switch rng.next() % 3 {
                case 0: bytes[index] = UInt8(truncatingIfNeeded: rng.next())
                case 1: bytes[index] ^= 0x80
                default: bytes.removeSubrange(index..<min(bytes.count, index + 1))
                }
            }
            if (try? RuleBundleLoader.load(bytes)) == nil { refused += 1 } else { accepted += 1 }
        }
        print("entid-fuzz: \(rounds) mutated bundles, \(refused) refused, \(accepted) accepted")
    }

    /// Bytes with no relation to a bundle at all.
    static func fuzzDecoderFromNothing(_ rng: inout Rng, rounds: Int) {
        for round in 0..<rounds {
            var bytes: [UInt8] = []
            for _ in 0...(round % 512) { bytes.append(UInt8(truncatingIfNeeded: rng.next())) }
            precondition(
                (try? RuleBundleLoader.load(bytes)) == nil,
                "random bytes were accepted as a ruleset"
            )
        }
        print("entid-fuzz: \(rounds) arbitrary payloads, all refused")
    }
}

/// A seeded xorshift, so that a finding is reproducible from its seed alone.
struct Rng {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        if state == 0 { state = 0x9E37_79B9_7F4A_7C15 }
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    /// Reaches the awkward parts on purpose: the frozen whitespace table,
    /// combining marks, an astral plane scalar and the separators
    /// canonicalization removes.
    mutating func string(upTo maximum: Int) -> String {
        let alphabet: [Unicode.Scalar] =
            Array("0123456789ABCXYZabcxyz -./_+".unicodeScalars) + [
                "\u{00A0}", "\u{FEFF}", "\u{3000}", "\u{0301}", "\u{200B}", "\u{202F}", "\u{1F600}",
                "\u{10FFFF}",
            ]
        var scalars = String.UnicodeScalarView()
        let count = maximum == 0 ? 0 : Int(next() % UInt64(maximum))
        for _ in 0..<count { scalars.append(alphabet[Int(next() % UInt64(alphabet.count))]) }
        return String(scalars)
    }
}
