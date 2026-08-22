/// The typed operations of a validated program.
///
/// Every parameter an opcode declares is carried here, already checked. A
/// value that reached one of these cases satisfied check 12 — the operation
/// carries only the parameters it declares, and every required one — and check
/// 13, the arithmetic bounds. The emitter therefore never re-reads a raw field
/// and never has to ask whether one is present.

package enum StringOp: Sendable, Hashable {
    case constant(String)
    case value
    case subject
    case countryCode
    case slice(start: Int, end: Int)
    case sliceFrom(start: Int)
    case sliceTo(end: Int)
    case beforeFirst(String)
    case afterFirst(String)
    case stripPrefix(String)
    case concat

    package var opcode: Opcode {
        switch self {
        case .constant: .stringConstant
        case .value: .stringValue
        case .subject: .stringSubject
        case .countryCode: .stringCountryCode
        case .slice: .stringSlice
        case .sliceFrom: .stringSliceFrom
        case .sliceTo: .stringSliceTo
        case .beforeFirst: .stringBeforeFirst
        case .afterFirst: .stringAfterFirst
        case .stripPrefix: .stringStripPrefix
        case .concat: .stringConcat
        }
    }
}

package enum IntegerOp: Sendable, Hashable {
    case digitsToInteger
    case modDigits(modulus: Int64)
    case weightedSum(
        weights: [Int64],
        alignment: WeightAlignment,
        mapping: CharMapping,
        alphabet: [Unicode.Scalar]?
    )
    case modulo(modulus: Int64)
    case complement(modulus: Int64)
    case remainderMap(values: [Int64])

    package var opcode: Opcode {
        switch self {
        case .digitsToInteger: .integerDigitsToInteger
        case .modDigits: .integerModDigits
        case .weightedSum: .integerWeightedSum
        case .modulo: .integerModulo
        case .complement: .integerComplement
        case .remainderMap: .integerRemainderMap
        }
    }
}

package enum PredicateOp: Sendable, Hashable {
    case isEmpty
    case isAbsent
    case equals
    case lengthEq(Int)
    case lengthIn([Int])
    case lengthBetween(min: Int, max: Int)
    case asciiDigits
    case asciiUpperLetters
    case asciiAlphanumeric
    case asciiCharset([Unicode.Scalar])
    case startsWith(String)
    case endsWith(String)
    case prefixIn([String])
    case charAtIn(index: Int, chars: [Unicode.Scalar])
    case contains(String)
    case all
    case any
    case not
    case profileIs(String)
    case integerIs(Int64)

    package var opcode: Opcode {
        switch self {
        case .isEmpty: .predicateIsEmpty
        case .isAbsent: .predicateIsAbsent
        case .equals: .predicateEquals
        case .lengthEq: .predicateLengthEq
        case .lengthIn: .predicateLengthIn
        case .lengthBetween: .predicateLengthBetween
        case .asciiDigits: .predicateAsciiDigits
        case .asciiUpperLetters: .predicateAsciiUpperLetters
        case .asciiAlphanumeric: .predicateAsciiAlphanumeric
        case .asciiCharset: .predicateAsciiCharset
        case .startsWith: .predicateStartsWith
        case .endsWith: .predicateEndsWith
        case .prefixIn: .predicatePrefixIn
        case .charAtIn: .predicateCharAtIn
        case .contains: .predicateContains
        case .all: .predicateAll
        case .any: .predicateAny
        case .not: .predicateNot
        case .profileIs: .predicateProfileIs
        case .integerIs: .predicateIntegerIs
        }
    }
}

package enum CanonicalOp: Sendable, Hashable {
    case sequence
    case trimWhitespace
    case removeWhitespace
    case uppercaseASCII
    case removeChars([Unicode.Scalar])
    case replacePrefix(text: String, replacement: String)
    case prepend(String)
    case append(String)
    case insert(index: Int, text: String)
    case leftPad(length: Int, pad: Unicode.Scalar)
    case prependCountryIfMissing
    case when

    package var opcode: Opcode {
        switch self {
        case .sequence: .canonicalSequence
        case .trimWhitespace: .canonicalTrimWhitespace
        case .removeWhitespace: .canonicalRemoveWhitespace
        case .uppercaseASCII: .canonicalUppercaseASCII
        case .removeChars: .canonicalRemoveChars
        case .replacePrefix: .canonicalReplacePrefix
        case .prepend: .canonicalPrepend
        case .append: .canonicalAppend
        case .insert: .canonicalInsert
        case .leftPad: .canonicalLeftPad
        case .prependCountryIfMissing: .canonicalPrependCountryIfMissing
        case .when: .canonicalWhen
        }
    }
}

package enum AssertionOp: Sendable, Hashable {
    case sequence
    case require(reason: ReasonCode, messageKey: String?)

    package var opcode: Opcode {
        switch self {
        case .sequence: .assertionSequence
        case .require: .assertionRequire
        }
    }
}

package enum ChecksumOp: Sendable, Hashable {
    case luhn(messageKey: String?)
    case iso7064Mod97Dash10(messageKey: String?)
    case compareDigit(index: Int, messageKey: String?)
    case compareSlice(start: Int, end: Int, messageKey: String?)
    case choose
    case when
    case allChecks
    case anyCheck
    case unsupported(reason: ReasonCode, messageKey: String?)
    case compareConstant(constant: Int64, messageKey: String?)

    package var opcode: Opcode {
        switch self {
        case .luhn: .checksumLuhn
        case .iso7064Mod97Dash10: .checksumISO7064Mod97_10
        case .compareDigit: .checksumCompareDigit
        case .compareSlice: .checksumCompareSlice
        case .choose: .checksumChoose
        case .when: .checksumWhen
        case .allChecks: .checksumAllChecks
        case .anyCheck: .checksumAnyCheck
        case .unsupported: .checksumUnsupported
        case .compareConstant: .checksumCompareConstant
        }
    }
}

package enum CallOp: Sendable, Hashable {
    case format(programID: UInt32)
    case checksum(programID: UInt32)

    package var opcode: Opcode {
        switch self {
        case .format: .callFormat
        case .checksum: .callChecksum
        }
    }

    package var programID: UInt32 {
        switch self {
        case .format(let identifier), .checksum(let identifier): identifier
        }
    }
}

package enum Operation: Sendable, Hashable {
    case string(StringOp)
    case integer(IntegerOp)
    case predicate(PredicateOp)
    case canonical(CanonicalOp)
    case assertion(AssertionOp)
    case checksum(ChecksumOp)
    case call(CallOp)

    package var opcode: Opcode {
        switch self {
        case .string(let operation): operation.opcode
        case .integer(let operation): operation.opcode
        case .predicate(let operation): operation.opcode
        case .canonical(let operation): operation.opcode
        case .assertion(let operation): operation.opcode
        case .checksum(let operation): operation.opcode
        case .call(let operation): operation.opcode
        }
    }
}
