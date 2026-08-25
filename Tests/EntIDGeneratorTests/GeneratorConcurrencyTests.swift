import Testing

@testable import EntIDGenerator

/// The generator under concurrency.
///
/// `engine.md` section 12.3 asks that the same bundle bytes loaded at the same
/// time yield equivalent engines. The generator is where that is decided here:
/// two maintainers regenerating at once, or a build system loading in parallel,
/// must not be able to produce two different sets of emitted files.
@Suite("Generator concurrency")
struct GeneratorConcurrencyTests {
    @Test("The same bytes loaded concurrently give equivalent bundles")
    func concurrentLoads() async throws {
        let bytes = try SpecCorpus.rulesBundle()
        let reference = try RuleBundleLoader.load(bytes)

        let loaded = await withTaskGroup(of: ExpansionProfile?.self) { group in
            for _ in 0..<16 {
                group.addTask { try? RuleBundleLoader.load(bytes).expansion }
            }
            var results: [ExpansionProfile?] = []
            for await result in group { results.append(result) }
            return results
        }

        #expect(loaded.count == 16)
        for profile in loaded {
            #expect(profile == reference.expansion)
        }
    }

    @Test("Emission is deterministic: the same bundle gives byte identical files")
    func emissionIsDeterministic() async throws {
        let bytes = try SpecCorpus.rulesBundle()

        let renders = await withTaskGroup(of: [String]?.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    guard let bundle = try? RuleBundleLoader.load(bytes) else { return nil }
                    return SwiftEmitter(bundle: bundle).emit().map(\.contents)
                }
            }
            var results: [[String]?] = []
            for await result in group { results.append(result) }
            return results
        }

        let first = try #require(renders.compactMap { $0 }.first)
        #expect(first.count == 3)
        for render in renders {
            // Nothing in the emitter may depend on a hash map's iteration
            // order, on a clock, or on which task got there first.
            #expect(render == first)
        }
    }

    @Test("Loading is a pure function of the bytes")
    func loadingIsPure() throws {
        let bytes = try SpecCorpus.rulesBundle()
        let first = try RuleBundleLoader.load(bytes)
        let second = try RuleBundleLoader.load(bytes)

        #expect(first.rulesVersion == second.rulesVersion)
        #expect(first.expansion == second.expansion)
        #expect(first.programs.count == second.programs.count)
        for (left, right) in zip(first.programs, second.programs) {
            #expect(left.id == right.id)
            #expect(left.nodes == right.nodes)
            #expect(left.root == right.root)
            #expect(left.captures == right.captures)
        }
    }
}
