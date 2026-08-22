import BusinessID
import BusinessIDGenerator
import Foundation

/// Regression benchmarks for the five shapes `engine.md` section 14 names:
/// cold load, a simple validation, a complex checksum, an input rejected early,
/// and parallel execution.
///
/// The numbers are not normative and no threshold fails a build. They exist so
/// that a change which quietly makes validation ten times slower shows up in a
/// pull request instead of in a consumer's profile.
///
///     businessid-bench [--iterations N]
@main
struct Bench {
    static func main() async {
        var iterations = 200_000
        var arguments = CommandLine.arguments.dropFirst().makeIterator()
        while let argument = arguments.next() {
            if argument == "--iterations" { iterations = arguments.next().flatMap(Int.init) ?? iterations }
        }

        print("businessid-bench: \(iterations) iterations per case, release build recommended")
        print("")

        // Cold load has nothing to measure in the engine: the rules are code,
        // so the first validation is the only cost there is. What is measured
        // instead is the generator, which pays that cost once at build time.
        if let bundle = FileManager.default.contents(atPath: "spec/businessid-rules.binpb") {
            measure("generator: load and check a bundle", iterations: 20) {
                _ = try? RuleBundleLoader.load([UInt8](bundle))
            }
        }

        let engine = BusinessIDEngine.default
        // `siren-validate-format-050`: a short format with a Luhn checksum.
        let simple = IdentifierInput(kind: "siren", value: "012345674")
        // `vat-fr-canonicalize-030`: canonicalization prepends a country prefix.
        let canonicalizing = IdentifierInput(kind: "vat", value: "09 012345674", countryCode: "FR")
        // `euid-fr-validate-format-021`: a composed format reusing another rule.
        let composed = IdentifierInput(kind: "euid", value: "FRTVX.012345675")
        // Rejected before any rule runs.
        let unknownKind = IdentifierInput(kind: "no_such_kind", value: "X")
        let tooLong = IdentifierInput(kind: "siren", value: String(repeating: "1", count: 2000))

        measure("validate: simple format and checksum", iterations: iterations) {
            blackHole(engine.validate(simple))
        }
        measure("validate: canonicalization with a prefix", iterations: iterations) {
            blackHole(engine.validate(canonicalizing))
        }
        measure("validate: composed format reusing a rule", iterations: iterations) {
            blackHole(engine.validate(composed))
        }
        measure("canonicalize only", iterations: iterations) {
            blackHole(engine.canonicalize(canonicalizing))
        }
        measure("reject early: unknown kind", iterations: iterations) {
            blackHole(engine.validate(unknownKind))
        }
        measure("reject early: input above the byte bound", iterations: iterations) {
            blackHole(engine.validate(tooLong))
        }

        await measureParallel("parallel validation across tasks", iterations: iterations)
    }

    static func measure(_ name: String, iterations: Int, _ body: () -> Void) {
        // One untimed pass, so that a first-use table does not land in the
        // measurement of the loop.
        body()
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations { body() }
        report(name, iterations: iterations, nanoseconds: DispatchTime.now().uptimeNanoseconds - start)
    }

    static func measureParallel(_ name: String, iterations: Int) async {
        let engine = BusinessIDEngine.default
        let inputs = (0..<8).map { index in
            IdentifierInput(kind: "siren", value: "01234567\(index % 10)")
        }
        let perTask = max(1, iterations / 8)

        let start = DispatchTime.now().uptimeNanoseconds
        await withTaskGroup(of: Void.self) { group in
            for input in inputs {
                group.addTask {
                    for _ in 0..<perTask { blackHole(engine.validate(input)) }
                }
            }
        }
        report(
            name,
            iterations: perTask * inputs.count,
            nanoseconds: DispatchTime.now().uptimeNanoseconds - start
        )
    }

    static func report(_ name: String, iterations: Int, nanoseconds: UInt64) {
        let each = Double(nanoseconds) / Double(iterations)
        let perSecond = each > 0 ? 1_000_000_000 / each : 0
        let padded = name.padding(toLength: max(name.count, 46), withPad: " ", startingAt: 0)
        print(
            "\(padded)  \(String(format: "%9.0f", each)) ns/op"
                + "  \(String(format: "%12.0f", perSecond))/s"
        )
    }

    /// Keeps the optimizer from deleting work whose result nobody reads.
    @inline(never)
    static func blackHole<T>(_ value: T) {
        withExtendedLifetime(value) {}
    }
}
