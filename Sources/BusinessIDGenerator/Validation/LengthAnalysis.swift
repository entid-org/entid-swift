/// The half of check 13 that reads a whole expression rather than one node:
/// the provable widths and the proof that no sum can overflow.
///
/// `ir.md` section 2 bounds what one public operation may materialize: the step
/// budget times sixty four code points. That is the ceiling every string
/// expression obeys, and it is what makes a weighted sum over a view the engine
/// cannot measure statically still provably safe.
enum LengthAnalysis {
    /// The normative ceiling on code points one public operation materializes.
    static let materializationCeiling = Limits.evaluationBudget * Limits.codePointsBilledAsOneStep

    static func check(nodes: [IRNode], programID: UInt32) throws(LoadError) {
        let widths = widths(of: nodes)

        for (index, node) in nodes.enumerated() {
            func reject(_ detail: String) -> LoadError {
                .invalidRuleset("program \(programID) node \(index): \(detail)")
            }
            guard case .integer(let operation) = node.operation else { continue }

            switch operation {
            case .digitsToInteger:
                // Accepted only when the maximum length of the operand is
                // provably at most eighteen code points. A longer or unbounded
                // view must use the digit by digit `mod_digits` family instead.
                let width = widths[node.inputs[0]]
                guard Limits.provableDigitsRange.contains(width) else {
                    throw reject(
                        "digits_to_integer reads a view of up to \(width) code points, beyond "
                            + "\(Limits.provableDigitsRange.upperBound)"
                    )
                }

            case .weightedSum(let weights, let alignment, let mapping, let alphabet):
                let positions =
                    switch alignment {
                    // LEFT and RIGHT only pair min(len(expr), len(weights))
                    // positions, so the weight list alone bounds the sum.
                    case .left, .right: min(widths[node.inputs[0]], weights.count)
                    case .cycle: widths[node.inputs[0]]
                    }
                let largestMapped: Int64 =
                    switch mapping {
                    case .digitValue: 9
                    case .alnumBase36: 35
                    case .customAlphabet: Int64((alphabet?.count ?? 1) - 1)
                    }
                let largestWeight = weights.map { abs($0) }.max() ?? 0
                let (perPosition, firstOverflow) = largestMapped.multipliedReportingOverflow(by: largestWeight)
                let (total, secondOverflow) = perPosition.multipliedReportingOverflow(by: Int64(positions))
                guard !firstOverflow, !secondOverflow, total >= 0 else {
                    throw reject("weighted_sum cannot be proved free of overflow")
                }

            case .modDigits, .modulo, .complement, .remainderMap:
                // Each is bounded by its own modulus or table, and each guards
                // its operand before computing, so no accumulation exists to
                // overflow.
                continue
            }
        }
    }

    /// The provable maximum number of code points each node yields, capped at
    /// the materialization ceiling.
    static func widths(of nodes: [IRNode]) -> [Int] {
        var widths = [Int](repeating: materializationCeiling, count: nodes.count)
        for (index, node) in nodes.enumerated() {
            guard case .string(let operation) = node.operation else { continue }
            let operandWidth = node.inputs.first.map { widths[$0] } ?? materializationCeiling
            let width: Int =
                switch operation {
                case .constant(let text): text.unicodeScalars.count
                // The canonical value and a caller supplied view are bounded by
                // what one operation may materialize and by nothing narrower.
                case .value, .subject: materializationCeiling
                case .countryCode: 2
                case .slice(let start, let end): max(0, end - start)
                case .sliceFrom(let start): max(0, operandWidth - start)
                case .sliceTo(let end): min(end, operandWidth)
                // Each of these yields a part of its operand, never more.
                case .beforeFirst, .afterFirst, .stripPrefix: operandWidth
                case .concat:
                    node.inputs.reduce(0) { partial, operand in
                        let (sum, overflow) = partial.addingReportingOverflow(widths[operand])
                        return overflow ? materializationCeiling : sum
                    }
                }
            widths[index] = min(width, materializationCeiling)
        }
        return widths
    }
}
