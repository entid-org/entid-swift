/// Every V1 opcode, named as `ir.md` names it.
///
/// The enumeration is closed on purpose. An opcode this generator does not
/// know never becomes a member: it is refused at check 10 as `invalid_ruleset`,
/// because a bundle legitimately using a newer operation would have declared
/// the capability that introduced it and stopped at check 4 instead.
package enum Opcode: String, Sendable, Hashable, CaseIterable {
    // String
    case stringConstant = "STRING_OP_KIND_CONSTANT"
    case stringValue = "STRING_OP_KIND_VALUE"
    case stringSubject = "STRING_OP_KIND_SUBJECT"
    case stringCountryCode = "STRING_OP_KIND_COUNTRY_CODE"
    case stringSlice = "STRING_OP_KIND_SLICE"
    case stringSliceFrom = "STRING_OP_KIND_SLICE_FROM"
    case stringSliceTo = "STRING_OP_KIND_SLICE_TO"
    case stringBeforeFirst = "STRING_OP_KIND_BEFORE_FIRST"
    case stringAfterFirst = "STRING_OP_KIND_AFTER_FIRST"
    case stringStripPrefix = "STRING_OP_KIND_STRIP_PREFIX"
    case stringConcat = "STRING_OP_KIND_CONCAT"

    // Integer
    case integerDigitsToInteger = "INTEGER_OP_KIND_DIGITS_TO_INTEGER"
    case integerModDigits = "INTEGER_OP_KIND_MOD_DIGITS"
    case integerWeightedSum = "INTEGER_OP_KIND_WEIGHTED_SUM"
    case integerModulo = "INTEGER_OP_KIND_MODULO"
    case integerComplement = "INTEGER_OP_KIND_COMPLEMENT"
    case integerRemainderMap = "INTEGER_OP_KIND_REMAINDER_MAP"

    // Predicate
    case predicateIsEmpty = "PREDICATE_OP_KIND_IS_EMPTY"
    case predicateIsAbsent = "PREDICATE_OP_KIND_IS_ABSENT"
    case predicateEquals = "PREDICATE_OP_KIND_EQUALS"
    case predicateLengthEq = "PREDICATE_OP_KIND_LENGTH_EQ"
    case predicateLengthIn = "PREDICATE_OP_KIND_LENGTH_IN"
    case predicateLengthBetween = "PREDICATE_OP_KIND_LENGTH_BETWEEN"
    case predicateAsciiDigits = "PREDICATE_OP_KIND_ASCII_DIGITS"
    case predicateAsciiUpperLetters = "PREDICATE_OP_KIND_ASCII_UPPER_LETTERS"
    case predicateAsciiAlphanumeric = "PREDICATE_OP_KIND_ASCII_ALPHANUMERIC"
    case predicateAsciiCharset = "PREDICATE_OP_KIND_ASCII_CHARSET"
    case predicateStartsWith = "PREDICATE_OP_KIND_STARTS_WITH"
    case predicateEndsWith = "PREDICATE_OP_KIND_ENDS_WITH"
    case predicatePrefixIn = "PREDICATE_OP_KIND_PREFIX_IN"
    case predicateCharAtIn = "PREDICATE_OP_KIND_CHAR_AT_IN"
    case predicateContains = "PREDICATE_OP_KIND_CONTAINS"
    case predicateAll = "PREDICATE_OP_KIND_ALL"
    case predicateAny = "PREDICATE_OP_KIND_ANY"
    case predicateNot = "PREDICATE_OP_KIND_NOT"
    case predicateProfileIs = "PREDICATE_OP_KIND_PROFILE_IS"
    case predicateIntegerIs = "PREDICATE_OP_KIND_INTEGER_IS"

    // Canonicalization
    case canonicalSequence = "CANONICALIZATION_OP_KIND_SEQUENCE"
    case canonicalTrimWhitespace = "CANONICALIZATION_OP_KIND_TRIM_WHITESPACE"
    case canonicalRemoveWhitespace = "CANONICALIZATION_OP_KIND_REMOVE_WHITESPACE"
    case canonicalUppercaseASCII = "CANONICALIZATION_OP_KIND_UPPERCASE_ASCII"
    case canonicalRemoveChars = "CANONICALIZATION_OP_KIND_REMOVE_CHARS"
    case canonicalReplacePrefix = "CANONICALIZATION_OP_KIND_REPLACE_PREFIX"
    case canonicalPrepend = "CANONICALIZATION_OP_KIND_PREPEND"
    case canonicalAppend = "CANONICALIZATION_OP_KIND_APPEND"
    case canonicalInsert = "CANONICALIZATION_OP_KIND_INSERT"
    case canonicalLeftPad = "CANONICALIZATION_OP_KIND_LEFT_PAD"
    case canonicalPrependCountryIfMissing = "CANONICALIZATION_OP_KIND_PREPEND_COUNTRY_IF_MISSING"
    case canonicalWhen = "CANONICALIZATION_OP_KIND_WHEN"

    // Assertion
    case assertionSequence = "ASSERTION_OP_KIND_SEQUENCE"
    case assertionRequire = "ASSERTION_OP_KIND_REQUIRE"

    // Checksum
    case checksumLuhn = "CHECKSUM_OP_KIND_LUHN"
    case checksumIso7064Mod9710 = "CHECKSUM_OP_KIND_ISO7064_MOD97_10"
    case checksumCompareDigit = "CHECKSUM_OP_KIND_COMPARE_DIGIT"
    case checksumCompareSlice = "CHECKSUM_OP_KIND_COMPARE_SLICE"
    case checksumChoose = "CHECKSUM_OP_KIND_CHOOSE"
    case checksumWhen = "CHECKSUM_OP_KIND_WHEN"
    case checksumAllChecks = "CHECKSUM_OP_KIND_ALL_CHECKS"
    case checksumAnyCheck = "CHECKSUM_OP_KIND_ANY_CHECK"
    case checksumUnsupported = "CHECKSUM_OP_KIND_UNSUPPORTED"
    case checksumCompareConstant = "CHECKSUM_OP_KIND_COMPARE_CONSTANT"

    // Call
    case callFormat = "CALL_OP_KIND_FORMAT"
    case callChecksum = "CALL_OP_KIND_CHECKSUM"
}

/// How many operands an opcode takes and of which type.
///
/// `ir.md` section 3 states an operand list per opcode: a fixed prefix, then an
/// optional repeated tail with its own bounds. Both are checked at check 11.
package struct OperandSpec: Sendable {
    package let fixed: [ValueType]
    package let repeatedType: ValueType?
    package let repeatedRange: ClosedRange<Int>?

    init(_ fixed: [ValueType] = [], repeating: ValueType? = nil, count: ClosedRange<Int>? = nil) {
        self.fixed = fixed
        repeatedType = repeating
        repeatedRange = count
    }
}

extension Opcode {
    /// The output type `ir.md` declares for this opcode.
    package var outputType: ValueType {
        switch self {
        case .stringConstant, .stringValue, .stringSubject, .stringCountryCode, .stringSlice,
            .stringSliceFrom, .stringSliceTo, .stringBeforeFirst, .stringAfterFirst,
            .stringStripPrefix, .stringConcat:
            .string
        case .integerDigitsToInteger, .integerModDigits, .integerWeightedSum, .integerModulo,
            .integerComplement, .integerRemainderMap:
            .integer
        case .predicateIsEmpty, .predicateIsAbsent, .predicateEquals, .predicateLengthEq,
            .predicateLengthIn, .predicateLengthBetween, .predicateAsciiDigits,
            .predicateAsciiUpperLetters, .predicateAsciiAlphanumeric, .predicateAsciiCharset,
            .predicateStartsWith, .predicateEndsWith, .predicatePrefixIn, .predicateCharAtIn,
            .predicateContains, .predicateAll, .predicateAny, .predicateNot, .predicateProfileIs,
            .predicateIntegerIs:
            .boolean
        case .canonicalSequence, .canonicalTrimWhitespace, .canonicalRemoveWhitespace,
            .canonicalUppercaseASCII, .canonicalRemoveChars, .canonicalReplacePrefix,
            .canonicalPrepend, .canonicalAppend, .canonicalInsert, .canonicalLeftPad,
            .canonicalPrependCountryIfMissing, .canonicalWhen:
            .canonicalizationStep
        case .assertionSequence, .assertionRequire, .callFormat:
            .assertion
        case .checksumLuhn, .checksumIso7064Mod9710, .checksumCompareDigit, .checksumCompareSlice,
            .checksumChoose, .checksumWhen, .checksumAllChecks, .checksumAnyCheck,
            .checksumUnsupported, .checksumCompareConstant, .callChecksum:
            .checksumOutcome
        }
    }

    /// The operand list `ir.md` section 3 states for this opcode.
    package var operands: OperandSpec {
        // An unbounded repeated tail is still bounded by the per program node
        // limit, so `Limits.maximumNodesPerProgram` stands for "unbounded".
        let unbounded = Limits.maximumNodesPerProgram
        switch self {
        case .stringConstant, .stringValue, .stringSubject, .stringCountryCode,
            .predicateProfileIs, .checksumUnsupported,
            .canonicalTrimWhitespace, .canonicalRemoveWhitespace, .canonicalUppercaseASCII,
            .canonicalRemoveChars, .canonicalReplacePrefix, .canonicalPrepend, .canonicalAppend,
            .canonicalInsert, .canonicalLeftPad, .canonicalPrependCountryIfMissing:
            return OperandSpec()

        case .stringSlice, .stringSliceFrom, .stringSliceTo, .stringBeforeFirst, .stringAfterFirst,
            .stringStripPrefix, .integerDigitsToInteger, .integerModDigits, .integerWeightedSum,
            .predicateIsEmpty, .predicateIsAbsent, .predicateLengthEq, .predicateLengthIn,
            .predicateLengthBetween, .predicateAsciiDigits, .predicateAsciiUpperLetters,
            .predicateAsciiAlphanumeric, .predicateAsciiCharset, .predicateStartsWith,
            .predicateEndsWith, .predicatePrefixIn, .predicateCharAtIn, .predicateContains,
            .checksumLuhn, .checksumIso7064Mod9710, .callFormat, .callChecksum:
            return OperandSpec([.string])

        case .stringConcat:
            return OperandSpec(repeating: .string, count: Limits.concatOperandRange)

        case .integerModulo, .integerComplement, .integerRemainderMap, .predicateIntegerIs,
            .checksumCompareConstant:
            return OperandSpec([.integer])

        case .predicateEquals:
            return OperandSpec([.string, .string])

        case .predicateAll, .predicateAny:
            return OperandSpec(repeating: .boolean, count: 1...unbounded)

        case .predicateNot, .assertionRequire:
            return OperandSpec([.boolean])

        case .canonicalSequence:
            return OperandSpec(repeating: .canonicalizationStep, count: 0...unbounded)

        case .canonicalWhen:
            return OperandSpec([.boolean], repeating: .canonicalizationStep, count: 1...unbounded)

        case .assertionSequence:
            return OperandSpec(repeating: .assertion, count: 1...unbounded)

        case .checksumCompareDigit, .checksumCompareSlice:
            return OperandSpec([.integer, .string])

        case .checksumChoose, .checksumAllChecks, .checksumAnyCheck:
            return OperandSpec(repeating: .checksumOutcome, count: 1...unbounded)

        case .checksumWhen:
            return OperandSpec([.boolean, .checksumOutcome])
        }
    }

    /// The capabilities `ir.md` section 3 and `features.md` attach to this
    /// opcode. A bundle using the opcode must declare every one of them.
    package var capabilities: [UInt32] {
        let core = Capability.coreGraphV1
        switch self {
        case .stringConstant, .stringValue, .stringSubject:
            return [core]
        case .stringCountryCode:
            return [core, Capability.identifierDispatchV1]
        case .stringSlice, .stringSliceFrom, .stringSliceTo, .stringBeforeFirst, .stringAfterFirst,
            .stringStripPrefix, .stringConcat, .predicateIsAbsent:
            return [core, Capability.stringViewsV1]

        case .integerDigitsToInteger, .integerModDigits, .integerModulo, .integerComplement,
            .integerRemainderMap:
            return [core, Capability.checksumTristateV1]
        case .integerWeightedSum:
            return [core, Capability.checksumTristateV1, Capability.checksumWeightedV1]

        case .predicateIsEmpty, .predicateEquals, .predicateLengthEq, .predicateLengthIn,
            .predicateLengthBetween, .predicateStartsWith, .predicateEndsWith, .predicatePrefixIn,
            .predicateCharAtIn, .predicateContains, .predicateAll, .predicateAny, .predicateNot,
            .assertionSequence, .assertionRequire:
            return [core, Capability.formatAssertionsV1]
        case .predicateAsciiDigits, .predicateAsciiUpperLetters, .predicateAsciiAlphanumeric,
            .predicateAsciiCharset:
            return [core, Capability.asciiAndWhitespaceV1]
        case .predicateProfileIs:
            return [core, Capability.profilesV1]
        case .predicateIntegerIs:
            return [core, Capability.checksumTristateV1, Capability.checksumIntegerPredicateV1]

        case .canonicalSequence, .canonicalRemoveChars, .canonicalReplacePrefix, .canonicalPrepend,
            .canonicalAppend, .canonicalInsert, .canonicalLeftPad:
            return [core, Capability.canonicalizationBasicV1]
        case .canonicalTrimWhitespace, .canonicalRemoveWhitespace, .canonicalUppercaseASCII:
            return [core, Capability.asciiAndWhitespaceV1, Capability.canonicalizationBasicV1]
        case .canonicalPrependCountryIfMissing:
            return [core, Capability.canonicalizationBasicV1, Capability.identifierDispatchV1]
        case .canonicalWhen:
            return [core, Capability.canonicalizationConditionalV1]

        case .checksumCompareDigit, .checksumCompareSlice, .checksumChoose, .checksumWhen,
            .checksumAllChecks, .checksumAnyCheck, .checksumUnsupported:
            return [core, Capability.checksumTristateV1]
        case .checksumLuhn:
            return [core, Capability.checksumTristateV1, Capability.checksumLuhnV1]
        case .checksumIso7064Mod9710:
            return [core, Capability.checksumTristateV1, Capability.checksumMod97V1]
        case .checksumCompareConstant:
            return [core, Capability.checksumTristateV1, Capability.checksumCompareConstantV1]

        case .callFormat:
            return [core, Capability.capturesAndCallsV1, Capability.formatAssertionsV1]
        case .callChecksum:
            return [core, Capability.capturesAndCallsV1, Capability.checksumTristateV1]
        }
    }
}
