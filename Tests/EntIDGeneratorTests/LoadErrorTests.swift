import Testing

@testable import EntIDGenerator

@Suite("Typed refusals")
struct LoadErrorTests {
    @Test("The wire name is what the conformance protocol expects")
    func wireNames() {
        #expect(LoadError.invalidRuleset("x").engineErrorName == "invalid_ruleset")
        #expect(LoadError.incompatibleRuleset("x").engineErrorName == "incompatible_ruleset")
    }

    @Test("The reason travels without its typed prefix")
    func reasons() {
        #expect(LoadError.invalidRuleset("a truncated bundle").reason == "a truncated bundle")
        #expect(LoadError.incompatibleRuleset("format_version 2").reason == "format_version 2")
    }

    @Test("The description names both the type and the reason")
    func descriptions() {
        #expect(LoadError.invalidRuleset("no root").description == "invalid_ruleset: no root")
        #expect(
            LoadError.incompatibleRuleset("capability 99").description
                == "incompatible_ruleset: capability 99"
        )
    }

    @Test("A loaded bundle resolves a program by its bundle id, not by position")
    func programLookup() throws {
        let bundle = try RuleBundleLoader.load(try SpecCorpus.rulesBundle())
        let first = try #require(bundle.programs.first)
        #expect(bundle.program(id: first.id)?.id == first.id)
        #expect(bundle.program(id: 0) == nil)
        #expect(bundle.program(id: 999_999) == nil)

        // Ids are assigned from one after sorting symbol names, so a program's
        // id is not its index and the map is not decoration.
        for program in bundle.programs {
            #expect(bundle.program(id: program.id)?.id == program.id)
        }
    }

    @Test("The capability registry names every id it knows")
    func capabilityNames() {
        for identifier in Capability.known.sorted() {
            let name = Capability.name(of: identifier)
            #expect(!name.hasPrefix("UNKNOWN"), Comment(rawValue: name))
            #expect(name.hasSuffix("_V1"), Comment(rawValue: name))
        }
        #expect(Capability.name(of: 9999) == "UNKNOWN(9999)")
    }
}
