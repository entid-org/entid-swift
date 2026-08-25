/// Check 14: expansion within the evaluation budget once repeated operands are
/// inlined.
///
/// The node count of a program is bounded, but the graph is a DAG, and a DAG
/// whose every node reads the previous one twice expands exponentially while
/// passing every other load check. Without this bound such a bundle is a denial
/// of service against the generator rather than against the engine.
///
/// The count is what a generator emits, and everything below follows from that.
enum Expansion {
    /// Saturating rather than wrapping. A chain two hundred levels deep reaches
    /// 2^201 instances, and an accumulator that wraps lands on a small number
    /// that passes: the overflow is the shape of the attack, not an edge case.
    static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : sum
    }

    /// The instances one emission root costs: one for the node itself, plus the
    /// cost of every operand it reads. A `CALL` counts as one instance and does
    /// not expand its callee, which is a separate program emitted once and
    /// bounded on its own — but the operand it computes is still emitted here.
    static func costs(of program: IRProgram) -> [Int] {
        var costs = [Int](repeating: 0, count: program.nodes.count)
        for (index, node) in program.nodes.enumerated() {
            var total = 1
            for operand in node.inputs {
                total = saturatingAdd(total, costs[operand])
            }
            costs[index] = total
        }
        return costs
    }

    /// The emission roots of a program, in the order their costs are charged.
    ///
    /// The roots are the program root, the `subject_node` when the program
    /// declares one, and every capture no other root already reaches. A capture
    /// any root reaches is not a second emission: it is emitted inside that
    /// root's expression, and counting its subtree again charges it twice.
    ///
    /// Captures are taken from the highest index down. An operand always sits
    /// at a lower index than the node reading it, so a capture reached by
    /// another is seen after the one reaching it and one pass settles it.
    /// Walking the capture list in its own order would make the count depend on
    /// how the captures happen to be listed, which is not an observable
    /// property of the bundle.
    static func emissionRoots(of program: IRProgram) -> [Int] {
        var reached = [Bool](repeating: false, count: program.nodes.count)

        func mark(_ index: Int) {
            guard !reached[index] else { return }
            reached[index] = true
            for operand in program.nodes[index].inputs { mark(operand) }
        }

        var roots: [Int] = [program.root]
        mark(program.root)
        if let subject = program.subject, !reached[subject] {
            roots.append(subject)
            mark(subject)
        }
        for capture in program.captures.sorted(by: { $0.node > $1.node }) where !reached[capture.node] {
            roots.append(capture.node)
            mark(capture.node)
        }
        return roots
    }

    /// The instances a program costs. Root costs are summed, because a
    /// generator emits all of them: checking each root separately would let a
    /// program carry any number of roots just below the ceiling.
    static func instances(of program: IRProgram) -> Int {
        let costs = costs(of: program)
        return emissionRoots(of: program).reduce(0) { saturatingAdd($0, costs[$1]) }
    }

    /// Measures every program and refuses the bundle when one exceeds the
    /// budget. A generated program may not carry more instances than an
    /// interpreter would have taken steps to run it once.
    static func profile(of programs: [IRProgram]) throws(LoadError) -> ExpansionProfile {
        var total = 0
        var worst = (id: UInt32(0), instances: 0, nodes: 0)
        for program in programs {
            let count = instances(of: program)
            guard count <= Limits.evaluationBudget else {
                throw LoadError.invalidRuleset(
                    "program \(program.id) expands to \(count) operation instances, "
                        + "beyond the budget of \(Limits.evaluationBudget)"
                )
            }
            total = saturatingAdd(total, count)
            if count > worst.instances {
                worst = (program.id, count, program.nodes.count)
            }
        }
        return ExpansionProfile(
            programCount: programs.count,
            totalInstances: total,
            worstProgramID: worst.id,
            worstInstances: worst.instances,
            worstNodeCount: worst.nodes
        )
    }
}
