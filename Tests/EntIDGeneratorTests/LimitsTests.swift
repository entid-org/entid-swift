import Testing

@testable import EntIDGenerator

/// The limits of `ir.md` section 8 are normative. An engine may raise an
/// internal limit and never lower it, so they are asserted literally rather
/// than derived from anything.
@Suite("IR limits")
struct LimitsTests {
    @Test("Structural limits match ir.md section 8")
    func structuralLimits() {
        #expect(Limits.maximumBundleBytes == 16_777_216)
        #expect(Limits.maximumIdentifiers == 10000)
        #expect(Limits.maximumTotalNodes == 500_000)
        #expect(Limits.maximumNodesPerProgram == 4096)
        #expect(Limits.maximumCallDepth == 32)
        #expect(Limits.maximumConstantBytes == 4096)
        #expect(Limits.maximumUserInputBytes == 1024)
        #expect(Limits.evaluationBudget == 100_000)
        #expect(Limits.codePointsBilledAsOneStep == 64)
        #expect(Limits.maximumCapturesPerFormat == 128)
    }

    @Test("Arithmetic limits match ir.md section 8")
    func arithmeticLimits() {
        #expect(Limits.modulusRange == 2...1_000_000_000)
        #expect(Limits.weightMagnitudeRange == 0...1_000_000)
        #expect(Limits.weightCountRange == 1...256)
        #expect(Limits.remainderMapCountRange == 1...1_000_000)
        #expect(Limits.indexRange == 0...4096)
        #expect(Limits.comparisonConstantRange == -1_000_000_000...1_000_000_000)
        #expect(Limits.concatOperandRange == 1...256)
        #expect(Limits.provableDigitsRange == 1...18)
        #expect(Limits.customAlphabetRange == 1...256)
    }

    @Test("rules_version shape limits match ir.md check 6")
    func rulesVersionLimits() {
        #expect(Limits.maximumRulesVersionBytes == 64)
    }
}

/// `features.md` freezes eighteen capability ids. The registry is a closed set:
/// a bundle declaring a single unknown id is `incompatible_ruleset`.
@Suite("Capability registry")
struct CapabilityTests {
    @Test("The eighteen frozen capability ids are known")
    func knownIdentifiers() {
        #expect(Capability.known == [1, 2, 3, 4, 5, 10, 11, 20, 21, 30, 31, 32, 33, 34, 35, 40, 41, 42])
    }

    @Test("An id outside the registry is unknown")
    func unknownIdentifiers() {
        #expect(!Capability.known.contains(0))
        #expect(!Capability.known.contains(6))
        #expect(!Capability.known.contains(43))
        #expect(!Capability.known.contains(UInt32.max))
    }

    @Test("Named constants match their frozen numbers")
    func namedConstants() {
        #expect(Capability.coreGraphV1 == 1)
        #expect(Capability.asciiAndWhitespaceV1 == 2)
        #expect(Capability.canonicalizationBasicV1 == 3)
        #expect(Capability.canonicalizationConditionalV1 == 4)
        #expect(Capability.identifierDispatchV1 == 5)
        #expect(Capability.stringViewsV1 == 10)
        #expect(Capability.capturesAndCallsV1 == 11)
        #expect(Capability.formatAssertionsV1 == 20)
        #expect(Capability.profilesV1 == 21)
        #expect(Capability.checksumTristateV1 == 30)
        #expect(Capability.checksumLuhnV1 == 31)
        #expect(Capability.checksumMod97V1 == 32)
        #expect(Capability.checksumWeightedV1 == 33)
        #expect(Capability.checksumCompareConstantV1 == 34)
        #expect(Capability.checksumIntegerPredicateV1 == 35)
        #expect(Capability.provenanceV1 == 40)
        #expect(Capability.provenanceTierV1 == 41)
        #expect(Capability.checksumCustomAlphabetV1 == 42)
    }
}
