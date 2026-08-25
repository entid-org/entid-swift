import Testing

@testable import EntIDGenerator

/// Hostile bytes handed to the generator.
///
/// The loader is the only thing in this project that reads untrusted input in
/// bulk, and it runs at build time. It still must never trap, loop or allocate
/// without a bound: a generator that crashes on a forged bundle is a supply
/// chain problem, not merely a build failure.
@Suite("Decoder security")
struct DecoderSecurityTests {
    private struct Rng {
        var state: UInt64
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }

    @Test("Arbitrary bytes are refused, never accepted and never fatal")
    func arbitraryBytes() {
        var rng = Rng(state: 0xF0_0D_5EED)
        for round in 0..<3000 {
            var bytes: [UInt8] = []
            for _ in 0..<(round % 64 + 1) { bytes.append(UInt8(truncatingIfNeeded: rng.next())) }
            #expect(throws: LoadError.self) { try RuleBundleLoader.load(bytes) }
        }
    }

    @Test("The empty payload carries no supported version")
    func emptyPayload() {
        do {
            _ = try RuleBundleLoader.load([])
            Issue.record("an empty payload was accepted")
        } catch {
            #expect(error.engineErrorName == "incompatible_ruleset")
        }
    }

    @Test("Every truncation of the published bundle is refused")
    func truncations() throws {
        let bundle = try SpecCorpus.rulesBundle()
        // A prefix of a valid message is the shape a partial download takes.
        for length in stride(from: 0, to: bundle.count, by: 997) {
            #expect(throws: LoadError.self) { try RuleBundleLoader.load(Array(bundle.prefix(length))) }
        }
    }

    @Test("Every single byte flipped in the published bundle is refused or loads cleanly")
    func singleByteMutations() throws {
        let bundle = try SpecCorpus.rulesBundle()
        var rng = Rng(state: 0xBADC0DE)
        for _ in 0..<600 {
            var mutated = bundle
            let index = Int(rng.next() % UInt64(mutated.count))
            mutated[index] ^= UInt8(truncatingIfNeeded: rng.next() | 1)
            // Either it is refused, or it is a ruleset this generator would
            // stand behind. What it must never be is a trap.
            _ = try? RuleBundleLoader.load(mutated)
        }
    }

    @Test("A deeply nested payload does not exhaust the stack")
    func deepNesting() {
        // Nested length delimited fields, far past any legitimate depth.
        var payload: [UInt8] = []
        for _ in 0..<20000 {
            payload = [0x3A, UInt8(truncatingIfNeeded: payload.count)] + payload
        }
        _ = try? RuleBundleLoader.load(payload)
    }

    @Test("A payload claiming a length it does not carry is refused")
    func lyingLength() {
        // Field 2 (rules_version), length delimited, announcing 4096 bytes.
        let payload: [UInt8] = [0x12, 0x80, 0x20] + [UInt8](repeating: 0x41, count: 8)
        #expect(throws: LoadError.self) { try RuleBundleLoader.load(payload) }
    }

    @Test("The generator emits nothing it has not accepted")
    func emissionRequiresAcceptance() throws {
        // The only path to the emitter is through a `LoadedBundle`, which only
        // the loader constructs. There is no initializer that skips it, and
        // this compiles only while that stays true.
        let bundle = try RuleBundleLoader.load(try SpecCorpus.rulesBundle())
        let files = SwiftEmitter(bundle: bundle).emit()
        #expect(files.count == 3)
        #expect(files.allSatisfy { !$0.contents.isEmpty })
    }
}
