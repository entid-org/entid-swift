import Testing

@testable import BusinessID

/// The engine holds no state, so sharing it needs no lock. These cases prove
/// the claim rather than asserting it: the same inputs are validated from many
/// tasks at once and must produce results identical to the sequential ones.
@Suite("Concurrency")
struct ConcurrencyTests {
    static let inputs: [IdentifierInput] = [
        IdentifierInput(kind: "siren", value: "  012 345-674 "),
        IdentifierInput(kind: "siren", value: "01234567"),
        IdentifierInput(kind: "vat", value: "gr 012345670"),
        IdentifierInput(kind: "vat", value: "BE0123456749", countryCode: "FR"),
        IdentifierInput(kind: "lei", value: "0000-0000-0000-0000-0098"),
        IdentifierInput(kind: "cegjegyzekszam", value: "0123456789"),
        IdentifierInput(kind: "no_such_kind", value: "X"),
        IdentifierInput(kind: "euid", value: "fr tvx.012345674"),
    ]

    @Test("Concurrent validations agree with the sequential ones")
    func concurrentValidate() async {
        let expected = Self.inputs.map { BusinessIDEngine.default.validate($0) }

        let observed = await withTaskGroup(of: (Int, ValidationReport).self) { group in
            for round in 0..<256 {
                let index = round % Self.inputs.count
                group.addTask {
                    (index, BusinessIDEngine.default.validate(Self.inputs[index]))
                }
            }
            var results: [(Int, ValidationReport)] = []
            for await result in group { results.append(result) }
            return results
        }

        #expect(observed.count == 256)
        for (index, report) in observed {
            #expect(report == expected[index])
        }
    }

    @Test("Concurrent canonicalizations agree with the sequential ones")
    func concurrentCanonicalize() async {
        let expected = Self.inputs.map { BusinessIDEngine.default.canonicalize($0) }

        let observed = await withTaskGroup(of: (Int, CanonicalizationResult).self) { group in
            for round in 0..<256 {
                let index = round % Self.inputs.count
                group.addTask { (index, BusinessIDEngine.default.canonicalize(Self.inputs[index])) }
            }
            var results: [(Int, CanonicalizationResult)] = []
            for await result in group { results.append(result) }
            return results
        }

        for (index, result) in observed {
            #expect(result == expected[index])
        }
    }

    @Test("Separately created engines are equivalent to the shared one")
    func freshEnginesAreEquivalent() async {
        let shared = Self.inputs.map { BusinessIDEngine.default.validate($0) }
        let fresh = await withTaskGroup(of: [ValidationReport].self) { group in
            for _ in 0..<16 {
                group.addTask {
                    let engine = BusinessIDEngine()
                    return Self.inputs.map { engine.validate($0) }
                }
            }
            var results: [[ValidationReport]] = []
            for await result in group { results.append(result) }
            return results
        }
        for run in fresh { #expect(run == shared) }
    }

    @Test("No validation state survives between two calls")
    func noStateBetweenCalls() {
        let engine = BusinessIDEngine.default
        let first = engine.validate(Self.inputs[0])
        _ = engine.validate(Self.inputs[3])
        _ = engine.canonicalize(Self.inputs[6])
        #expect(engine.validate(Self.inputs[0]) == first)
    }
}
