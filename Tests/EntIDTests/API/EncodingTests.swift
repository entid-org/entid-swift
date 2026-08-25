import Foundation
import Testing

@testable import EntID

/// `ReasonCode.invalidEncoding` is unreachable through this API, and this is
/// the test that pins why.
///
/// `ir.md` section 5 step 1 refuses input that is not valid UTF-8 with
/// `unsupported`/`invalidEncoding`, and states that no conformance case can
/// carry it: a proto3 `string` is valid UTF-8 by definition, and there is no
/// portable malformed value to carry — an invalid byte where strings are
/// bytes, an unpaired surrogate where they are UTF-16 code units, and nothing
/// at all where they are always well formed.
///
/// Swift is the third case. Every engine pins the step with a native test
/// naming the malformed form its own string type admits; Swift's `String`
/// admits none, so what is pinned here is that fact, with the two forms other
/// languages would use shown to be unrepresentable.
///
/// The alternative would be a byte oriented entry point on the public API that
/// exists only to reach this branch. `engine-swift.md` says not to, and it is
/// right: a public type is a commitment SemVer freezes, and this one would
/// exist to serve a reason code rather than a caller.
///
/// Since `2026.08.31` `ir.md` section 6 step 1 states the consequence for the
/// input bound as well, and it is what this suite already relied on. The bound
/// counts UTF-8 bytes and runs *before* the step that refuses ill formed text,
/// so an engine whose string type admits such text has to choose what to count
/// and MUST say which — a lone surrogate encodes to one replacement byte
/// through a platform encoder and to three through the encoding it would have
/// had. Swift's `String` admits none, so there is no choice to state and no
/// answer to defend: every value that reaches this API already has exactly one
/// UTF-8 encoding.
///
/// What was reasoning here is now normative text, and nothing in this engine
/// changed to meet it.
@Suite("Encoding")
struct EncodingTests {
    // UTF-8 decoding that repairs rather than refuses.
    //
    // This is the whole subject of the suite: the repairing initializer is
    // what turns bytes nobody can represent into text everybody can, so the
    // failable one SwiftLint prefers would leave nothing to hand the engine.
    // It is asserted separately, on the line that belongs to it.
    // swiftlint:disable:next optional_data_string_conversion
    static func repairing(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self) }

    /// The same, from UTF-16 code units.
    static func repairingUTF16(_ units: [UInt16]) -> String { String(decoding: units, as: UTF16.self) }

    /// The form a language whose strings are bytes would use.
    @Test("An invalid byte cannot survive into a String")
    func invalidByteIsRepairedOrRefused() {
        // 0xFF is not a legal byte anywhere in UTF-8.
        let illFormed: [UInt8] = [0x41, 0xFF, 0x42]

        // The failable initializer refuses it outright.
        #expect(String(bytes: illFormed, encoding: .utf8) == nil)

        // The repairing one substitutes U+FFFD, so what reaches an API is well
        // formed text that happens to contain a replacement character. That is
        // an ordinary code point, not a malformed one.
        //
        let repaired = Self.repairing(illFormed)
        #expect(repaired == "A\u{FFFD}B")
        #expect(repaired.unicodeScalars.count == 3)
        #expect(Array(repaired.utf8) != illFormed)
    }

    /// The form a language whose strings are UTF-16 code units would use.
    @Test("An unpaired surrogate cannot be built at all")
    func unpairedSurrogateIsUnrepresentable() {
        // A lone high or low surrogate is not a Unicode scalar value, and
        // `Unicode.Scalar` is exactly the set of scalar values.
        #expect(Unicode.Scalar(0xD800) == nil)
        #expect(Unicode.Scalar(0xDBFF) == nil)
        #expect(Unicode.Scalar(0xDC00) == nil)
        #expect(Unicode.Scalar(0xDFFF) == nil)

        // Decoding a lone surrogate from UTF-16 yields the replacement
        // character, so this route produces well formed text too.
        let lone: [UInt16] = [0x0041, 0xD800, 0x0042]
        #expect(Self.repairingUTF16(lone) == "A\u{FFFD}B")
    }

    @Test("The engine never reports invalidEncoding, whatever it is handed")
    func theEngineNeverReportsIt() {
        // Every string these produce is well formed by construction, which is
        // the point: there is nothing to hand the engine that would reach the
        // branch.
        let engine = EntIDEngine.default
        let awkward: [String] = [
            Self.repairing([0x41, 0xFF, 0x42]),
            Self.repairing([0xC0, 0x80]),  // overlong NUL
            Self.repairing([0xED, 0xA0, 0x80]),  // surrogate in UTF-8
            Self.repairing([0xF5, 0x80, 0x80, 0x80]),  // beyond U+10FFFF
            Self.repairingUTF16([0x0041, 0xD800, 0x0042]),
            "\u{FFFD}",
            "\u{0000}",
            "\u{10FFFF}",
        ]

        for value in awkward {
            for kind in ["siren", "vat", "lei"] {
                let input = IdentifierInput(kind: IdentifierKind(kind), value: value)
                let report = engine.validate(input)
                #expect(
                    report.format.reasonCode != .invalidEncoding, Comment(rawValue: value.debugDescription))
                #expect(report.checksum.reasonCode != .invalidEncoding)
                #expect(engine.canonicalize(input).reasonCode != .invalidEncoding)
            }
        }
    }

    /// The bound is UTF-8 bytes, on the one input where the two readings of
    /// `ir.md` section 6 step 1 would separate elsewhere.
    ///
    /// U+FFFD is what a repairing decoder substitutes for an ill formed byte,
    /// and it occupies three UTF-8 bytes and one code point. An engine counting
    /// code points would accept 1024 of them — 3072 bytes — and one counting
    /// what its encoder produced for a surrogate would land somewhere else
    /// again. This asserts the byte count, at the boundary, from both sides.
    @Test("The input bound counts UTF-8 bytes, not code points")
    func theBoundCountsBytes() {
        let engine = EntIDEngine.default
        // 341 x 3 = 1023 bytes, one below the bound; 342 x 3 = 1026, past it.
        let under = String(repeating: "\u{FFFD}", count: 341)
        let over = String(repeating: "\u{FFFD}", count: 342)
        #expect(under.utf8.count == 1023 && under.unicodeScalars.count == 341)
        #expect(over.utf8.count == 1026 && over.unicodeScalars.count == 342)

        let accepted = engine.validate(IdentifierInput(kind: "siren", value: under))
        #expect(accepted.format.reasonCode != .inputTooLong)
        let refused = engine.validate(IdentifierInput(kind: "siren", value: over))
        #expect(refused.format.status == .unsupported)
        #expect(refused.format.reasonCode == .inputTooLong)
        // A safety bound is never a business verdict.
        #expect(refused.checksum.status == .notRun)
    }

    @Test("The reason code stays in the public registry, reachable or not")
    func theReasonCodeIsStillDeclared() {
        // Removing it would make this engine's registry disagree with the
        // specification's, and an engine on a platform whose strings admit
        // ill formed text does reach it.
        #expect(ReasonCode.allCases.contains(.invalidEncoding))
        #expect(ReasonCode.invalidEncoding.rawValue == "invalid_encoding")
    }
}
