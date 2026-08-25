/// The constant tables the emitted code reads.
///
/// Every literal of the ruleset is named once and shared. They are emitted as
/// Swift string literals rather than as code point numbers so that a rules
/// update reads as a diff a human can check: `"EL"` says what changed, a list
/// of integers does not.
struct LiteralTable {
    private(set) var scalarLiterals: [(name: String, text: String)] = []
    private(set) var scalarListLiterals: [(name: String, texts: [String])] = []
    private(set) var integerLiterals: [(name: String, values: [Int64])] = []
    private(set) var lengthLiterals: [(name: String, values: [Int])] = []

    private var scalarNames: [String: String] = [:]
    private var scalarListNames: [String: String] = [:]
    private var integerNames: [String: String] = [:]
    private var lengthNames: [String: String] = [:]

    /// A run of code points, such as a prefix, a delimiter or a character set.
    mutating func name(text: String) -> String {
        if let existing = scalarNames[text] { return existing }
        let name = "t\(scalarLiterals.count)"
        scalarNames[text] = name
        scalarLiterals.append((name, text))
        return name
    }

    mutating func name(scalars: [Unicode.Scalar]) -> String {
        name(text: String(String.UnicodeScalarView(scalars)))
    }

    /// A list of runs, such as the accepted prefixes of a target.
    mutating func name(texts: [String]) -> String {
        let key = texts.joined(separator: "\u{0}")
        if let existing = scalarListNames[key] { return existing }
        let name = "p\(scalarListLiterals.count)"
        scalarListNames[key] = name
        scalarListLiterals.append((name, texts))
        return name
    }

    /// A weight sequence or a remainder table.
    mutating func name(integers: [Int64]) -> String {
        let key = integers.map(String.init).joined(separator: ",")
        if let existing = integerNames[key] { return existing }
        let name = "w\(integerLiterals.count)"
        integerNames[key] = name
        integerLiterals.append((name, integers))
        return name
    }

    /// An accepted length set.
    mutating func name(lengths: [Int]) -> String {
        let key = lengths.map(String.init).joined(separator: ",")
        if let existing = lengthNames[key] { return existing }
        let name = "l\(lengthLiterals.count)"
        lengthNames[key] = name
        lengthLiterals.append((name, lengths))
        return name
    }

    func render() -> String {
        var out = SwiftSource()
        out.header(
            summary: "Constant tables the generated rules read.",
            detail: """
                Every literal appears once and is shared by every rule that uses
                it. They are `static let`, so each one is built on first use and
                never again; nothing here is constructed when a program starts.
                """
        )
        out.line("enum GeneratedLiterals {")
        out.push()
        for literal in scalarLiterals {
            out.line(
                "static let \(literal.name): [Unicode.Scalar] = "
                    + "Array(\(SwiftSource.quote(literal.text)).unicodeScalars)"
            )
        }
        for literal in scalarListLiterals {
            guard !literal.texts.isEmpty else {
                out.line("static let \(literal.name): [[Unicode.Scalar]] = []")
                continue
            }
            // Sorted by length first, code points second. The bundle presents
            // these ascending by UTF-8 bytes, which the loader checks; this is
            // the same order re-blocked so that every prefix of one length is
            // contiguous. `Predicates.prefixIn` binary searches each block, and
            // `engine.md` section 14 asks for a membership test that is not
            // linear in the size of the list.
            let ordered = literal.texts.sorted { left, right in
                let leftScalars = Array(left.unicodeScalars)
                let rightScalars = Array(right.unicodeScalars)
                if leftScalars.count != rightScalars.count { return leftScalars.count < rightScalars.count }
                for (one, other) in zip(leftScalars, rightScalars) where one.value != other.value {
                    return one.value < other.value
                }
                return false
            }
            let items = ordered.map(SwiftSource.quote).joined(separator: ", ")
            out.line(
                "static let \(literal.name): [[Unicode.Scalar]] = "
                    + "[\(items)].map { Array($0.unicodeScalars) }"
            )
        }
        for literal in integerLiterals {
            let items = literal.values.map(String.init).joined(separator: ", ")
            out.line("static let \(literal.name): [Int64] = [\(items)]")
        }
        for literal in lengthLiterals {
            let items = literal.values.map(String.init).joined(separator: ", ")
            out.line("static let \(literal.name): [Int] = [\(items)]")
        }
        out.pop()
        out.line("}")
        return out.text
    }
}
