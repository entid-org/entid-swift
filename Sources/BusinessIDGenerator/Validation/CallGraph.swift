/// Check 24: the call graph is acyclic, typed and of static depth at most 32.
///
/// The topological order of the nodes inside one program says nothing about
/// this: a program can reach itself through a chain of calls while every one of
/// its own nodes references a strictly lower index.
enum CallGraph {
    static func check(programs: [IRProgram], indexByID: [UInt32: Int]) throws(LoadError) {
        var depths = [Int?](repeating: nil, count: programs.count)
        var onStack = [Bool](repeating: false, count: programs.count)

        // The recursion is bounded by the depth limit itself: a chain longer
        // than 32 is refused before it can grow a stack.
        func depth(of index: Int) throws(LoadError) -> Int {
            if let known = depths[index] { return known }
            guard !onStack[index] else {
                throw LoadError.invalidRuleset("program \(programs[index].id) takes part in a call cycle")
            }
            onStack[index] = true
            defer { onStack[index] = false }

            var deepest = 0
            for node in programs[index].nodes {
                guard case .call(let call) = node.operation else { continue }
                guard let calleeIndex = indexByID[call.programID] else {
                    throw LoadError.invalidRuleset(
                        "program \(programs[index].id) calls unknown program \(call.programID)"
                    )
                }
                let callee = programs[calleeIndex]
                let expected: ProgramKind = switch call {
                case .format: .format
                case .checksum: .checksum
                }
                guard callee.kind == expected else {
                    throw LoadError.invalidRuleset(
                        "program \(programs[index].id) calls program \(callee.id) as a "
                            + "\(expected.rawValue) it is not"
                    )
                }
                deepest = max(deepest, try depth(of: calleeIndex))
            }

            let result = deepest + 1
            guard result <= Limits.maximumCallDepth else {
                throw LoadError.invalidRuleset(
                    "the call graph reaches depth \(result), beyond \(Limits.maximumCallDepth)"
                )
            }
            depths[index] = result
            return result
        }

        for index in programs.indices { _ = try depth(of: index) }
    }
}
