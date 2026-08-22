import BusinessIDConformance
import Foundation

/// Runs the shared corpus against the testee and reports every divergence.
///
///     businessid-conformance-runner [--cases spec/businessid-conformance.binpb]
@main
struct Run {
    static func main() {
        var path = "spec/businessid-conformance.binpb"
        var arguments = CommandLine.arguments.dropFirst().makeIterator()
        while let argument = arguments.next() {
            if argument == "--cases", let next = arguments.next() { path = next }
        }

        do {
            let runner = try ConformanceRunner(corpusPath: path)
            let outcome = try runner.run()
            for divergence in outcome.divergences {
                print(divergence.summary)
            }
            let passed = outcome.executed - Set(outcome.divergences.map(\.caseID)).count
            print("conformance: \(passed)/\(outcome.executed) cases, \(outcome.divergences.count) divergences")
            exit(outcome.isConformant ? 0 : 1)
        } catch {
            FileHandle.standardError.write(Data("conformance runner: \(error)\n".utf8))
            exit(2)
        }
    }
}
