internal import BusinessIDWire

/// Checks 10 to 13, applied to one node.
///
/// Lowering and validating are the same pass on purpose: a node becomes a
/// typed `Operation` only by presenting exactly the parameters its opcode
/// declares, inside the arithmetic bounds `ir.md` section 8 states. Nothing
/// downstream can then read a field the opcode does not own, because there is
/// no field left to read.
struct NodeLowering {
    let programID: UInt32
    let nodeIndex: Int

    private func reject(_ detail: String) -> LoadError {
        .invalidRuleset("program \(programID) node \(nodeIndex): \(detail)")
    }

    // MARK: - Entry

    func lower(_ node: Libbusinessid_Ir_V1_Node) throws(LoadError) -> IRNode {
        // Check 10: every operation known, with its declared output type. An
        // absent `oneof operation` is refused here rather than defaulted.
        guard let operation = node.operation else {
            throw reject("no operation oneof")
        }
        let lowered = try lower(operation)
        let opcode = lowered.opcode

        guard let outputType = ValueType(wire: node.outputType) else {
            throw reject("unrecognised output type")
        }
        guard outputType == opcode.outputType else {
            throw reject(
                "\(opcode.rawValue) declares \(opcode.outputType.rawValue), node says \(outputType.rawValue)"
            )
        }

        // Check 11: operand count and strictly lower operand indices. Operand
        // types are checked by the caller, which alone knows the earlier nodes.
        let spec = opcode.operands
        var inputs: [Int] = []
        inputs.reserveCapacity(node.inputNodes.count)
        for raw in node.inputNodes {
            let index = Int(raw)
            guard index < nodeIndex else {
                throw reject("operand \(index) is not a strictly lower index")
            }
            inputs.append(index)
        }
        let tail = inputs.count - spec.fixed.count
        if let range = spec.repeatedRange {
            guard tail >= 0, range.contains(tail) else {
                throw reject(
                    "\(opcode.rawValue) takes \(spec.fixed.count) then \(range) operands, got \(inputs.count)"
                )
            }
        } else {
            guard tail == 0 else {
                throw reject("\(opcode.rawValue) takes \(spec.fixed.count) operands, got \(inputs.count)")
            }
        }

        return IRNode(outputType: outputType, inputs: inputs, operation: lowered)
    }

    private func lower(
        _ operation: Libbusinessid_Ir_V1_Node.OneOf_Operation
    ) throws(LoadError) -> Operation {
        switch operation {
        case .stringOperation(let payload): .string(try lowerString(payload))
        case .integerOperation(let payload): .integer(try lowerInteger(payload))
        case .predicateOperation(let payload): .predicate(try lowerPredicate(payload))
        case .canonicalizationOperation(let payload): .canonical(try lowerCanonical(payload))
        case .assertionOperation(let payload): .assertion(try lowerAssertion(payload))
        case .checksumOperation(let payload): .checksum(try lowerChecksum(payload))
        case .callOperation(let payload): .call(try lowerCall(payload))
        }
    }

    // MARK: - Shared parameter guards

    /// Check 12: the presented parameters are exactly those the opcode owns.
    private func requireParameters(
        _ opcode: Opcode,
        present: Set<String>,
        required: Set<String>,
        optional: Set<String> = []
    ) throws(LoadError) {
        let stray = present.subtracting(required).subtracting(optional)
        guard stray.isEmpty else {
            throw reject(
                "\(opcode.rawValue) carries stray parameter(s) \(stray.sorted().joined(separator: ", "))")
        }
        let missing = required.subtracting(present)
        guard missing.isEmpty else {
            throw reject("\(opcode.rawValue) misses parameter(s) \(missing.sorted().joined(separator: ", "))")
        }
    }

    /// Check 13: a constant string is at most 4096 UTF-8 bytes.
    private func checkedConstant(_ text: String, _ label: String) throws(LoadError) -> String {
        guard text.utf8.count <= Limits.maximumConstantBytes else {
            throw reject("\(label) exceeds \(Limits.maximumConstantBytes) UTF-8 bytes")
        }
        return text
    }

    private func checkedNonEmpty(_ text: String, _ label: String) throws(LoadError) -> String {
        let value = try checkedConstant(text, label)
        guard !value.isEmpty else { throw reject("\(label) is empty") }
        return value
    }

    private func checkedASCIISet(_ text: String, _ label: String) throws(LoadError) -> [Unicode.Scalar] {
        let scalars = Array(try checkedNonEmpty(text, label).unicodeScalars)
        guard scalars.allSatisfy(TokenShape.isASCII) else {
            throw reject("\(label) holds a non ASCII code point")
        }
        return scalars
    }

    /// Check 13: an index or slice bound lies in `0..4096`.
    private func checkedIndex(_ value: UInt32, _ label: String) throws(LoadError) -> Int {
        guard Limits.indexRange.contains(Int64(value)) else {
            throw reject("\(label) \(value) is outside \(Limits.indexRange)")
        }
        return Int(value)
    }

    private func checkedModulus(_ value: Int64) throws(LoadError) -> Int64 {
        guard Limits.modulusRange.contains(value) else {
            throw reject("modulus \(value) is outside \(Limits.modulusRange)")
        }
        return value
    }

    private func checkedComparisonConstant(_ value: Int64, _ label: String) throws(LoadError) -> Int64 {
        guard Limits.comparisonConstantRange.contains(value) else {
            throw reject("\(label) \(value) is outside \(Limits.comparisonConstantRange)")
        }
        return value
    }

    /// `ir.md` section 6: a declared message key is never empty. A present but
    /// empty key cannot be told apart from an absent one in an idiomatic API,
    /// so two engines could report differently on the same bundle.
    private func checkedMessageKey(_ hasKey: Bool, _ key: String) throws(LoadError) -> String? {
        guard hasKey else { return nil }
        guard !key.isEmpty else { throw reject("message_key is present but empty") }
        return try checkedConstant(key, "message_key")
    }

    private func checkedReasonCode(
        _ raw: Libbusinessid_Ir_V1_ReasonCode,
        allowed: Set<ReasonCode>,
        label: String
    ) throws(LoadError) -> ReasonCode {
        guard let code = ReasonCode(wire: raw) else {
            throw reject("\(label) is not a known reason code")
        }
        guard allowed.contains(code) else {
            throw reject("\(label) \(code.rawValue) cannot carry the status this operation reports")
        }
        return code
    }

    // MARK: - String operations

    private func lowerString(
        _ payload: Libbusinessid_Ir_V1_StringOperation
    ) throws(LoadError) -> StringOp {
        var present: Set<String> = []
        if payload.hasText { present.insert("text") }
        if payload.hasStart { present.insert("start") }
        if payload.hasEnd { present.insert("end") }

        switch payload.kind {
        case .constant:
            try requireParameters(.stringConstant, present: present, required: ["text"])
            return .constant(try checkedConstant(payload.text, "text"))
        case .value:
            try requireParameters(.stringValue, present: present, required: [])
            return .value
        case .subject:
            try requireParameters(.stringSubject, present: present, required: [])
            return .subject
        case .countryCode:
            try requireParameters(.stringCountryCode, present: present, required: [])
            return .countryCode
        case .slice:
            try requireParameters(.stringSlice, present: present, required: ["start", "end"])
            return .slice(
                start: try checkedIndex(payload.start, "start"),
                end: try checkedIndex(payload.end, "end")
            )
        case .sliceFrom:
            try requireParameters(.stringSliceFrom, present: present, required: ["start"])
            return .sliceFrom(start: try checkedIndex(payload.start, "start"))
        case .sliceTo:
            try requireParameters(.stringSliceTo, present: present, required: ["end"])
            return .sliceTo(end: try checkedIndex(payload.end, "end"))
        case .beforeFirst:
            try requireParameters(.stringBeforeFirst, present: present, required: ["text"])
            return .beforeFirst(try checkedNonEmpty(payload.text, "text"))
        case .afterFirst:
            try requireParameters(.stringAfterFirst, present: present, required: ["text"])
            return .afterFirst(try checkedNonEmpty(payload.text, "text"))
        case .stripPrefix:
            try requireParameters(.stringStripPrefix, present: present, required: ["text"])
            return .stripPrefix(try checkedConstant(payload.text, "text"))
        case .concat:
            try requireParameters(.stringConcat, present: present, required: [])
            return .concat
        case .unspecified, .UNRECOGNIZED:
            throw reject("unknown string opcode")
        }
    }

    // MARK: - Integer operations

    private func lowerInteger(
        _ payload: Libbusinessid_Ir_V1_IntegerOperation
    ) throws(LoadError) -> IntegerOp {
        var present: Set<String> = []
        if payload.hasModulus { present.insert("modulus") }
        if !payload.weights.isEmpty { present.insert("weights") }
        if payload.hasAlignment { present.insert("alignment") }
        if payload.hasMapping { present.insert("mapping") }
        if !payload.remainderValues.isEmpty { present.insert("remainder_values") }
        if payload.hasAlphabet { present.insert("alphabet") }

        switch payload.kind {
        case .digitsToInteger:
            try requireParameters(.integerDigitsToInteger, present: present, required: [])
            return .digitsToInteger
        case .modDigits:
            try requireParameters(.integerModDigits, present: present, required: ["modulus"])
            return .modDigits(modulus: try checkedModulus(payload.modulus))
        case .modulo:
            try requireParameters(.integerModulo, present: present, required: ["modulus"])
            return .modulo(modulus: try checkedModulus(payload.modulus))
        case .complement:
            try requireParameters(.integerComplement, present: present, required: ["modulus"])
            return .complement(modulus: try checkedModulus(payload.modulus))
        case .remainderMap:
            try requireParameters(.integerRemainderMap, present: present, required: ["remainder_values"])
            guard Limits.remainderMapCountRange.contains(payload.remainderValues.count) else {
                throw reject("remainder table holds \(payload.remainderValues.count) elements")
            }
            return .remainderMap(values: payload.remainderValues)
        case .weightedSum:
            try requireParameters(
                .integerWeightedSum,
                present: present,
                required: ["weights", "alignment", "mapping"],
                optional: ["alphabet"]
            )
            guard Limits.weightCountRange.contains(payload.weights.count) else {
                throw reject("weighted_sum carries \(payload.weights.count) weights")
            }
            for weight in payload.weights {
                guard weight != .min, Limits.weightMagnitudeRange.contains(abs(weight)) else {
                    throw reject("weight \(weight) is outside magnitude \(Limits.weightMagnitudeRange)")
                }
            }
            guard let alignment = WeightAlignment(wire: payload.alignment) else {
                throw reject("unknown weight alignment")
            }
            guard let mapping = CharMapping(wire: payload.mapping) else {
                throw reject("unknown char mapping")
            }
            let alphabet = try checkedAlphabet(payload, mapping: mapping)
            return .weightedSum(
                weights: payload.weights,
                alignment: alignment,
                mapping: mapping,
                alphabet: alphabet
            )
        case .unspecified, .UNRECOGNIZED:
            throw reject("unknown integer opcode")
        }
    }

    /// `CHECKSUM_CUSTOM_ALPHABET_V1`: the alphabet is required by
    /// `CUSTOM_ALPHABET` and forbidden by the other mappings, holds one to two
    /// hundred fifty six code points, and lists none of them twice. A repeated
    /// code point would carry two values, and which one an engine returned
    /// would depend on how it searched.
    private func checkedAlphabet(
        _ payload: Libbusinessid_Ir_V1_IntegerOperation,
        mapping: CharMapping
    ) throws(LoadError) -> [Unicode.Scalar]? {
        guard mapping == .customAlphabet else {
            guard !payload.hasAlphabet else {
                throw reject("alphabet is stated under \(mapping.rawValue), which never reads it")
            }
            return nil
        }
        guard payload.hasAlphabet else {
            throw reject("CHAR_MAPPING_CUSTOM_ALPHABET requires an alphabet")
        }
        let scalars = Array(try checkedConstant(payload.alphabet, "alphabet").unicodeScalars)
        guard Limits.customAlphabetRange.contains(scalars.count) else {
            throw reject("alphabet holds \(scalars.count) code points, outside \(Limits.customAlphabetRange)")
        }
        guard Set(scalars).count == scalars.count else {
            throw reject("alphabet lists a code point twice")
        }
        return scalars
    }

    // MARK: - Predicate operations

    private func lowerPredicate(
        _ payload: Libbusinessid_Ir_V1_PredicateOperation
    ) throws(LoadError) -> PredicateOp {
        var present: Set<String> = []
        if payload.hasText { present.insert("text") }
        if !payload.values.isEmpty { present.insert("values") }
        if !payload.lengths.isEmpty { present.insert("lengths") }
        if payload.hasLength { present.insert("length") }
        if payload.hasMinLength { present.insert("min_length") }
        if payload.hasMaxLength { present.insert("max_length") }
        if payload.hasIndex { present.insert("index") }
        if payload.hasConstant { present.insert("constant") }

        switch payload.kind {
        case .isEmpty:
            try requireParameters(.predicateIsEmpty, present: present, required: [])
            return .isEmpty
        case .isAbsent:
            try requireParameters(.predicateIsAbsent, present: present, required: [])
            return .isAbsent
        case .equals:
            try requireParameters(.predicateEquals, present: present, required: [])
            return .equals
        case .lengthEq:
            try requireParameters(.predicateLengthEq, present: present, required: ["length"])
            return .lengthEq(try checkedIndex(payload.length, "length"))
        case .lengthIn:
            try requireParameters(.predicateLengthIn, present: present, required: ["lengths"])
            var lengths: [Int] = []
            for raw in payload.lengths { lengths.append(try checkedIndex(raw, "lengths element")) }
            guard zip(lengths, lengths.dropFirst()).allSatisfy({ $0 < $1 }) else {
                throw reject("lengths is not ascending and deduplicated")
            }
            return .lengthIn(lengths)
        case .lengthBetween:
            try requireParameters(
                .predicateLengthBetween, present: present, required: ["min_length", "max_length"]
            )
            let minimum = try checkedIndex(payload.minLength, "min_length")
            let maximum = try checkedIndex(payload.maxLength, "max_length")
            guard minimum <= maximum else { throw reject("min_length exceeds max_length") }
            return .lengthBetween(min: minimum, max: maximum)
        case .asciiDigits:
            try requireParameters(.predicateAsciiDigits, present: present, required: [])
            return .asciiDigits
        case .asciiUpperLetters:
            try requireParameters(.predicateAsciiUpperLetters, present: present, required: [])
            return .asciiUpperLetters
        case .asciiAlphanumeric:
            try requireParameters(.predicateAsciiAlphanumeric, present: present, required: [])
            return .asciiAlphanumeric
        case .asciiCharset:
            try requireParameters(.predicateAsciiCharset, present: present, required: ["text"])
            return .asciiCharset(try checkedASCIISet(payload.text, "text"))
        case .startsWith:
            try requireParameters(.predicateStartsWith, present: present, required: ["text"])
            return .startsWith(try checkedNonEmpty(payload.text, "text"))
        case .endsWith:
            try requireParameters(.predicateEndsWith, present: present, required: ["text"])
            return .endsWith(try checkedNonEmpty(payload.text, "text"))
        case .prefixIn:
            try requireParameters(.predicatePrefixIn, present: present, required: ["values"])
            var values: [String] = []
            for value in payload.values { values.append(try checkedNonEmpty(value, "values element")) }
            guard zip(values, values.dropFirst()).allSatisfy({ precedesByUTF8($0, $1) }) else {
                throw reject("values is not ascending and deduplicated")
            }
            return .prefixIn(values)
        case .charAtIn:
            try requireParameters(.predicateCharAtIn, present: present, required: ["index", "text"])
            return .charAtIn(
                index: try checkedIndex(payload.index, "index"),
                chars: try checkedASCIISet(payload.text, "text")
            )
        case .contains:
            try requireParameters(.predicateContains, present: present, required: ["text"])
            return .contains(try checkedNonEmpty(payload.text, "text"))
        case .all:
            try requireParameters(.predicateAll, present: present, required: [])
            return .all
        case .any:
            try requireParameters(.predicateAny, present: present, required: [])
            return .any
        case .not:
            try requireParameters(.predicateNot, present: present, required: [])
            return .not
        case .profileIs:
            try requireParameters(.predicateProfileIs, present: present, required: ["text"])
            let name = try checkedNonEmpty(payload.text, "text")
            guard name == "compatible" || name == "strict_current" else {
                throw reject("profile_is names \(name), which is not a V1 profile")
            }
            return .profileIs(name)
        case .integerIs:
            try requireParameters(.predicateIntegerIs, present: present, required: ["constant"])
            return .integerIs(try checkedComparisonConstant(payload.constant, "constant"))
        case .unspecified, .UNRECOGNIZED:
            throw reject("unknown predicate opcode")
        }
    }

    // MARK: - Canonicalization operations

    private func lowerCanonical(
        _ payload: Libbusinessid_Ir_V1_CanonicalizationOperation
    ) throws(LoadError) -> CanonicalOp {
        var present: Set<String> = []
        if payload.hasText { present.insert("text") }
        if payload.hasReplacement { present.insert("replacement") }
        if payload.hasIndex { present.insert("index") }
        if payload.hasLength { present.insert("length") }

        switch payload.kind {
        case .sequence:
            try requireParameters(.canonicalSequence, present: present, required: [])
            return .sequence
        case .trimWhitespace:
            try requireParameters(.canonicalTrimWhitespace, present: present, required: [])
            return .trimWhitespace
        case .removeWhitespace:
            try requireParameters(.canonicalRemoveWhitespace, present: present, required: [])
            return .removeWhitespace
        case .uppercaseAscii:
            try requireParameters(.canonicalUppercaseASCII, present: present, required: [])
            return .uppercaseASCII
        case .removeChars:
            try requireParameters(.canonicalRemoveChars, present: present, required: ["text"])
            return .removeChars(Array(try checkedNonEmpty(payload.text, "text").unicodeScalars))
        case .replacePrefix:
            try requireParameters(
                .canonicalReplacePrefix, present: present, required: ["text", "replacement"]
            )
            let text = try checkedNonEmpty(payload.text, "text")
            let replacement = try checkedConstant(payload.replacement, "replacement")
            guard text != replacement else { throw reject("replace_prefix replaces a prefix by itself") }
            return .replacePrefix(text: text, replacement: replacement)
        case .prepend:
            try requireParameters(.canonicalPrepend, present: present, required: ["text"])
            return .prepend(try checkedNonEmpty(payload.text, "text"))
        case .append:
            try requireParameters(.canonicalAppend, present: present, required: ["text"])
            return .append(try checkedNonEmpty(payload.text, "text"))
        case .insert:
            try requireParameters(.canonicalInsert, present: present, required: ["index", "text"])
            return .insert(
                index: try checkedIndex(payload.index, "index"),
                text: try checkedNonEmpty(payload.text, "text")
            )
        case .leftPad:
            try requireParameters(.canonicalLeftPad, present: present, required: ["length", "text"])
            // The bound matters beyond arithmetic: an engine that compiles the
            // rules sizes a buffer from this number.
            let length = try checkedIndex(payload.length, "length")
            guard length >= 1 else { throw reject("left_pad length is below one") }
            let scalars = Array(try checkedNonEmpty(payload.text, "text").unicodeScalars)
            guard scalars.count == 1 else { throw reject("left_pad pads with more than one code point") }
            return .leftPad(length: length, pad: scalars[0])
        case .prependCountryIfMissing:
            try requireParameters(.canonicalPrependCountryIfMissing, present: present, required: [])
            return .prependCountryIfMissing
        case .when:
            try requireParameters(.canonicalWhen, present: present, required: [])
            return .when
        case .unspecified, .UNRECOGNIZED:
            throw reject("unknown canonicalization opcode")
        }
    }

    // MARK: - Assertion operations

    private func lowerAssertion(
        _ payload: Libbusinessid_Ir_V1_AssertionOperation
    ) throws(LoadError) -> AssertionOp {
        var present: Set<String> = []
        if payload.hasReasonCode { present.insert("reason_code") }
        if payload.hasMessageKey { present.insert("message_key") }

        switch payload.kind {
        case .sequence:
            try requireParameters(.assertionSequence, present: present, required: [])
            return .sequence
        case .require:
            try requireParameters(
                .assertionRequire, present: present, required: ["reason_code"], optional: ["message_key"]
            )
            return .require(
                reason: try checkedReasonCode(
                    payload.reasonCode, allowed: ReasonCode.provingInvalidity, label: "reason_code"
                ),
                messageKey: try checkedMessageKey(payload.hasMessageKey, payload.messageKey)
            )
        case .unspecified, .UNRECOGNIZED:
            throw reject("unknown assertion opcode")
        }
    }

    // MARK: - Checksum operations

    private func lowerChecksum(
        _ payload: Libbusinessid_Ir_V1_ChecksumOperation
    ) throws(LoadError) -> ChecksumOp {
        var present: Set<String> = []
        if payload.hasIndex { present.insert("index") }
        if payload.hasStart { present.insert("start") }
        if payload.hasEnd { present.insert("end") }
        if payload.hasReasonCode { present.insert("reason_code") }
        if payload.hasMessageKey { present.insert("message_key") }
        if payload.hasConstant { present.insert("constant") }
        let key = ["message_key"] as Set<String>

        switch payload.kind {
        case .luhn:
            try requireParameters(.checksumLuhn, present: present, required: [], optional: key)
            return .luhn(messageKey: try checkedMessageKey(payload.hasMessageKey, payload.messageKey))
        case .iso7064Mod9710:
            try requireParameters(.checksumIso7064Mod9710, present: present, required: [], optional: key)
            return .iso7064Mod97Dash10(
                messageKey: try checkedMessageKey(payload.hasMessageKey, payload.messageKey)
            )
        case .compareDigit:
            try requireParameters(
                .checksumCompareDigit, present: present, required: ["index"], optional: key
            )
            return .compareDigit(
                index: try checkedIndex(payload.index, "index"),
                messageKey: try checkedMessageKey(payload.hasMessageKey, payload.messageKey)
            )
        case .compareSlice:
            try requireParameters(
                .checksumCompareSlice, present: present, required: ["start", "end"], optional: key
            )
            let start = try checkedIndex(payload.start, "start")
            let end = try checkedIndex(payload.end, "end")
            guard Limits.provableDigitsRange.contains(end - start) else {
                throw reject(
                    "compare_slice spans \(end - start) code points, outside \(Limits.provableDigitsRange)")
            }
            return .compareSlice(
                start: start,
                end: end,
                messageKey: try checkedMessageKey(payload.hasMessageKey, payload.messageKey)
            )
        case .choose:
            try requireParameters(.checksumChoose, present: present, required: [])
            return .choose
        case .when:
            try requireParameters(.checksumWhen, present: present, required: [])
            return .when
        case .allChecks:
            try requireParameters(.checksumAllChecks, present: present, required: [])
            return .allChecks
        case .anyCheck:
            try requireParameters(.checksumAnyCheck, present: present, required: [])
            return .anyCheck
        case .unsupported:
            try requireParameters(
                .checksumUnsupported, present: present, required: ["reason_code"], optional: key
            )
            return .unsupported(
                reason: try checkedReasonCode(
                    payload.reasonCode, allowed: ReasonCode.absentChecksum, label: "reason_code"
                ),
                messageKey: try checkedMessageKey(payload.hasMessageKey, payload.messageKey)
            )
        case .compareConstant:
            try requireParameters(
                .checksumCompareConstant, present: present, required: ["constant"], optional: key
            )
            return .compareConstant(
                constant: try checkedComparisonConstant(payload.constant, "constant"),
                messageKey: try checkedMessageKey(payload.hasMessageKey, payload.messageKey)
            )
        case .unspecified, .UNRECOGNIZED:
            throw reject("unknown checksum opcode")
        }
    }

    // MARK: - Call operations

    private func lowerCall(_ payload: Libbusinessid_Ir_V1_CallOperation) throws(LoadError) -> CallOp {
        switch payload.kind {
        case .format: .format(programID: payload.programID)
        case .checksum: .checksum(programID: payload.programID)
        case .unspecified, .UNRECOGNIZED: throw reject("unknown call opcode")
        }
    }
}
