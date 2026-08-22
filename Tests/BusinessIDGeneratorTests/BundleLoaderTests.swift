import Testing

@testable import BusinessIDGenerator

/// The generator against the artefacts of the release named by `rules.lock`.
@Suite("Bundle loader")
struct BundleLoaderTests {
    @Test("The published bundle loads")
    func publishedBundleLoads() throws {
        let bundle = try RuleBundleLoader.load(try SpecCorpus.rulesBundle())
        #expect(bundle.formatVersion == 1)
        #expect(bundle.rulesVersion == RulesLockFixture.rulesVersion)
        #expect(
            bundle.requiredFeatures == [1, 2, 3, 4, 5, 10, 11, 20, 21, 30, 31, 32, 33, 34, 35, 40, 41, 42])
        #expect(bundle.sourceDigest.count == 32)
        #expect(bundle.programs.count == 250)
        #expect(bundle.definitions.count == 94)
        #expect(bundle.dispatchers.count == 37)
        #expect(bundle.programs.reduce(0) { $0 + $1.nodes.count } == 2376)
    }

    @Test("The published bundle covers thirty seven countries")
    func countryCoverage() throws {
        let bundle = try RuleBundleLoader.load(try SpecCorpus.rulesBundle())
        let countries = Set(bundle.definitions.compactMap(\.countryCode))
        #expect(countries.count == 37)
    }

    /// The thirty four `load_ruleset` cases of the corpus, each addressed to
    /// the generator. The expectation compared is the typed error alone: the
    /// runner reads it, the generator never does.
    @Test("Every hostile bundle of the corpus is refused with the stated error")
    func hostileBundlesAreRefused() throws {
        let cases = try SpecCorpus.loaderCases()
        #expect(cases.count == 35)

        for testCase in cases {
            let observed: String
            do {
                _ = try RuleBundleLoader.load([UInt8](testCase.rulesPayload))
                observed = "accepted"
            } catch {
                observed = error.engineErrorName
            }
            #expect(
                observed == testCase.expectedEngineError,
                "\(testCase.id): \(testCase.description_p)"
            )
        }
    }
}
