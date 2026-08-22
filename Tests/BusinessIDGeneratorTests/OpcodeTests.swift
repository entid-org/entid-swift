import Testing

@testable import BusinessIDGenerator

/// `ir.md` states a capability list per opcode; `features.md` states the
/// reverse, an opcode list per capability. The generator encodes the first.
/// This suite transcribes the second and requires the two to agree — the only
/// way to notice that one of the two readings drifted.
@Suite("Opcode registry")
struct OpcodeTests {
    @Test("The registry holds the sixty three V1 opcodes")
    func opcodeCount() {
        #expect(Opcode.allCases.count == 63)
    }

    /// `features.md` section "Operations requiring this capability", transcribed.
    static let opcodesByCapability: [UInt32: Set<Opcode>] = [
        2: [
            .canonicalRemoveWhitespace, .canonicalTrimWhitespace, .canonicalUppercaseASCII,
            .predicateAsciiAlphanumeric, .predicateAsciiCharset, .predicateAsciiDigits,
            .predicateAsciiUpperLetters,
        ],
        3: [
            .canonicalAppend, .canonicalInsert, .canonicalLeftPad, .canonicalPrepend,
            .canonicalPrependCountryIfMissing, .canonicalRemoveChars, .canonicalRemoveWhitespace,
            .canonicalReplacePrefix, .canonicalSequence, .canonicalTrimWhitespace,
            .canonicalUppercaseASCII,
        ],
        4: [.canonicalWhen],
        5: [.canonicalPrependCountryIfMissing, .stringCountryCode],
        10: [
            .predicateIsAbsent, .stringAfterFirst, .stringBeforeFirst, .stringConcat, .stringSlice,
            .stringSliceFrom, .stringSliceTo, .stringStripPrefix,
        ],
        11: [.callChecksum, .callFormat],
        20: [
            .assertionRequire, .assertionSequence, .callFormat, .predicateAll, .predicateAny,
            .predicateCharAtIn, .predicateContains, .predicateEndsWith, .predicateEquals,
            .predicateIsEmpty, .predicateLengthBetween, .predicateLengthEq, .predicateLengthIn,
            .predicateNot, .predicatePrefixIn, .predicateStartsWith,
        ],
        21: [.predicateProfileIs],
        30: [
            .callChecksum, .checksumAllChecks, .checksumAnyCheck, .checksumChoose,
            .checksumCompareConstant, .checksumCompareDigit, .checksumCompareSlice,
            .checksumIso7064Mod9710, .checksumLuhn, .checksumUnsupported, .checksumWhen,
            .integerComplement, .integerDigitsToInteger, .integerModulo, .integerModDigits,
            .integerRemainderMap, .integerWeightedSum, .predicateIntegerIs,
        ],
        31: [.checksumLuhn],
        32: [.checksumIso7064Mod9710],
        33: [.integerWeightedSum],
        34: [.checksumCompareConstant],
        35: [.predicateIntegerIs],
        40: [],
        41: [],
        42: [],
    ]

    @Test("Every opcode requires CORE_GRAPH_V1")
    func coreGraphIsUniversal() {
        for opcode in Opcode.allCases {
            #expect(opcode.capabilities.contains(Capability.coreGraphV1), "\(opcode.rawValue)")
        }
    }

    @Test("The per opcode capability lists agree with features.md")
    func capabilityListsAgree() {
        for (capability, expected) in Self.opcodesByCapability {
            let actual = Set(Opcode.allCases.filter { $0.capabilities.contains(capability) })
            #expect(actual == expected, "capability \(Capability.name(of: capability))")
        }
    }

    @Test("An opcode declares no capability outside the frozen registry")
    func capabilitiesAreKnown() {
        for opcode in Opcode.allCases {
            for capability in opcode.capabilities {
                #expect(Capability.known.contains(capability), "\(opcode.rawValue)")
            }
        }
    }

    @Test("Output types match ir.md section 3")
    func outputTypes() {
        #expect(Opcode.stringConcat.outputType == .string)
        #expect(Opcode.integerWeightedSum.outputType == .integer)
        #expect(Opcode.predicateIntegerIs.outputType == .boolean)
        #expect(Opcode.canonicalWhen.outputType == .canonicalizationStep)
        #expect(Opcode.assertionRequire.outputType == .assertion)
        #expect(Opcode.callFormat.outputType == .assertion)
        #expect(Opcode.checksumChoose.outputType == .checksumOutcome)
        #expect(Opcode.callChecksum.outputType == .checksumOutcome)
    }

    @Test("Operand shapes match ir.md section 3")
    func operandShapes() {
        #expect(Opcode.stringValue.operands.fixed.isEmpty)
        #expect(Opcode.stringValue.operands.repeatedType == nil)

        let concat = Opcode.stringConcat.operands
        #expect(concat.fixed.isEmpty)
        #expect(concat.repeatedType == .string)
        #expect(concat.repeatedRange == 1...256)

        let when = Opcode.canonicalWhen.operands
        #expect(when.fixed == [.boolean])
        #expect(when.repeatedType == .canonicalizationStep)
        #expect(when.repeatedRange?.lowerBound == 1)

        let sequence = Opcode.canonicalSequence.operands
        #expect(sequence.repeatedRange?.lowerBound == 0)

        #expect(Opcode.assertionSequence.operands.repeatedRange?.lowerBound == 1)
        #expect(Opcode.checksumCompareDigit.operands.fixed == [.integer, .string])
        #expect(Opcode.checksumWhen.operands.fixed == [.boolean, .checksumOutcome])
        #expect(Opcode.predicateEquals.operands.fixed == [.string, .string])
    }
}
