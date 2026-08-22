/// Turns a validated bundle into the Swift the engine ships.
///
/// The emitted files are the library: there is no bundle at runtime, no
/// Protobuf decoder, and no machine that walks the IR. What a rule does is
/// Swift control flow that a reviewer can read in a diff.
package struct SwiftEmitter {
    package let bundle: LoadedBundle

    package init(bundle: LoadedBundle) {
        self.bundle = bundle
    }

    /// File name to contents, ready to be written under `Generated/`.
    package func emit() -> [(name: String, contents: String)] {
        var literals = LiteralTable()
        let programs = renderPrograms(literals: &literals)
        let ruleset = renderRuleset(literals: &literals)
        return [
            ("GeneratedLiterals.swift", literals.render()),
            ("GeneratedPrograms.swift", programs),
            ("GeneratedRuleset.swift", ruleset),
        ]
    }

    // MARK: - Programs

    private func renderPrograms(literals: inout LiteralTable) -> String {
        var out = SwiftSource()
        out.header(
            summary: "The rules, compiled to Swift.",
            detail: """
                One function per IR program, one local function per node. A node
                runs again at every reference, because nothing here is memoized:
                inside a canonicalization program `value()` means the value
                current at the moment the enclosing step runs.
                """
        )
        out.line("enum GeneratedPrograms {")
        out.push()
        var first = true
        for program in bundle.programs {
            if !first { out.line() }
            first = false
            ProgramEmitter(program: program).render(into: &out, literals: &literals)
        }
        out.pop()
        out.line("}")
        return out.text
    }

    // MARK: - Ruleset

    /// Targets are numbered across the whole bundle, in dispatcher order then
    /// target order, so one index identifies one routing entry.
    private var flattenedTargets: [(dispatcher: Int, target: DispatchTarget)] {
        var result: [(Int, DispatchTarget)] = []
        for (index, dispatcher) in bundle.dispatchers.enumerated() {
            for target in dispatcher.targets { result.append((index, target)) }
        }
        return result
    }

    private var definitionIndexByID: [UInt32: Int] {
        var result: [UInt32: Int] = [:]
        for (index, definition) in bundle.definitions.enumerated() { result[definition.id] = index }
        return result
    }

    private func renderRuleset(literals: inout LiteralTable) -> String {
        let targets = flattenedTargets
        let definitionIndex = definitionIndexByID

        var out = SwiftSource()
        out.header(
            summary: "Dispatch and definition tables, compiled to Swift.",
            detail: """
                Every lookup is a switch rather than a dictionary built at start
                up, so nothing is constructed before the first validation and
                nothing is shared between them.

                The integer indices are a closed space produced only by the
                lookups below; the `default` branches exist to satisfy the
                compiler on `Int` and are unreachable.
                """
        )
        out.line("enum GeneratedRuleset {")
        out.push()

        out.line("static let rulesVersion = \(SwiftSource.quote(bundle.rulesVersion))")
        out.line("static let formatVersion = \(bundle.formatVersion)")
        out.line(
            "static let capabilities: [Int] = "
                + "[\(bundle.requiredFeatures.map(String.init).joined(separator: ", "))]"
        )
        out.line("static let identifierCount = \(bundle.definitions.count)")
        out.line("static let countryCount = \(Set(bundle.definitions.compactMap(\.countryCode)).count)")
        let kinds = bundle.dispatchers.map { SwiftSource.quote($0.kind) }.joined(separator: ", ")
        out.line("static let canonicalKinds: [IdentifierKind] = [\(kinds)]")
        out.line()
        out.line("static let expansionProfile = \(SwiftSource.quote(bundle.expansion.summary))")
        out.line()

        renderKindDispatch(into: &out)
        renderCanonicalKind(into: &out)
        renderPreCanonicalization(into: &out)
        renderCountryAliases(into: &out)
        renderCountryTargets(into: &out, targets: targets)
        renderCountrySpecific(into: &out)
        renderPrefixTargets(into: &out, targets: targets, literals: &literals)
        renderImplicitTargets(into: &out, targets: targets)
        renderTargetCountry(into: &out, targets: targets, literals: &literals)
        renderDefinitionOfTarget(into: &out, targets: targets, definitionIndex: definitionIndex)
        renderDefaultProfile(into: &out)
        renderCanonicalize(
            into: &out, targets: targets, definitionIndex: definitionIndex, literals: &literals)
        renderFormat(into: &out)
        renderChecksum(into: &out)

        out.pop()
        out.line("}")
        return out.text
    }

    private func renderKindDispatch(into out: inout SwiftSource) {
        out.line("/// Step 2 and 3 of dispatch: the canonical kind and its aliases share one")
        out.line("/// space, which the load checks proved holds no duplicate.")
        out.line("static func dispatcher(forKind kind: String) -> Int? {")
        out.push()
        out.line("switch kind {")
        for (index, dispatcher) in bundle.dispatchers.enumerated() {
            let tokens = ([dispatcher.kind] + dispatcher.kindAliases).map(SwiftSource.quote)
            out.line("case \(tokens.joined(separator: ", ")): \(index)")
        }
        out.line("default: nil")
        out.line("}")
        out.pop()
        out.line("}")
        out.line()
    }

    private func renderCanonicalKind(into out: inout SwiftSource) {
        out.line("static func canonicalKind(_ dispatcher: Int) -> String {")
        out.push()
        out.line("switch dispatcher {")
        for (index, dispatcher) in bundle.dispatchers.enumerated() {
            out.line("case \(index): \(SwiftSource.quote(dispatcher.kind))")
        }
        out.line("default: \"\"")
        out.line("}")
        out.pop()
        out.line("}")
        out.line()
    }

    private func renderPreCanonicalization(into out: inout SwiftSource) {
        out.line("/// Step 4: the pre-canonicalization program runs once on the raw value,")
        out.line("/// before any country decision.")
        out.line(
            "static func preCanonicalize(_ dispatcher: Int, _ v: inout [Unicode.Scalar], "
                + "_ profile: ValidationProfile) {"
        )
        out.push()
        out.line("let c = CanonicalizationContext(profile: profile)")
        out.line("switch dispatcher {")
        for (index, dispatcher) in bundle.dispatchers.enumerated() {
            out.line(
                "case \(index): GeneratedPrograms.canon\(dispatcher.preCanonicalizationProgram)(&v, c)"
            )
        }
        out.line("default: break")
        out.line("}")
        out.pop()
        out.line("}")
        out.line()
    }

    private func renderCountryAliases(into out: inout SwiftSource) {
        out.line("static func resolveCountryAlias(_ dispatcher: Int, _ country: String) -> String {")
        out.push()
        out.line("switch dispatcher {")
        for (index, dispatcher) in bundle.dispatchers.enumerated()
        where !dispatcher.countryAliases.isEmpty {
            out.line("case \(index):")
            out.push()
            out.line("switch country {")
            for alias in dispatcher.countryAliases {
                out.line(
                    "case \(SwiftSource.quote(alias.alias)): return \(SwiftSource.quote(alias.countryCode))"
                )
            }
            out.line("default: return country")
            out.line("}")
            out.pop()
        }
        out.line("default: return country")
        out.line("}")
        out.pop()
        out.line("}")
        out.line()
    }

    private func renderCountryTargets(
        into out: inout SwiftSource,
        targets: [(dispatcher: Int, target: DispatchTarget)]
    ) {
        out.line("static func countryTarget(_ dispatcher: Int, _ country: String) -> Int? {")
        out.push()
        out.line("switch dispatcher {")
        for index in bundle.dispatchers.indices {
            let owned = targets.enumerated().filter { $0.element.dispatcher == index }
            let countries = owned.compactMap { entry -> (Int, String)? in
                entry.element.target.countryCode.map { (entry.offset, $0) }
            }
            guard !countries.isEmpty else { continue }
            out.line("case \(index):")
            out.push()
            out.line("switch country {")
            for (target, country) in countries {
                out.line("case \(SwiftSource.quote(country)): return \(target)")
            }
            out.line("default: return nil")
            out.line("}")
            out.pop()
        }
        out.line("default: return nil")
        out.line("}")
        out.pop()
        out.line("}")
        out.line()
    }

    private func renderCountrySpecific(into out: inout SwiftSource) {
        out.line("/// Step 5: in a country specific dispatcher a country without target is")
        out.line("/// `unsupported_country`; a GLOBAL dispatcher keeps the context instead.")
        out.line("static func isCountrySpecific(_ dispatcher: Int) -> Bool {")
        out.push()
        out.line("switch dispatcher {")
        for (index, dispatcher) in bundle.dispatchers.enumerated() {
            let global = dispatcher.targets.contains { $0.countryCode == nil }
            out.line("case \(index): \(global ? "false" : "true")")
        }
        out.line("default: false")
        out.line("}")
        out.pop()
        out.line("}")
        out.line()
    }

    /// One accepted prefix and the target claiming it, ordered by descending
    /// length so that the first match is the longest one.
    private struct PrefixEntry {
        let prefix: String
        let target: Int
        var length: Int { prefix.unicodeScalars.count }
    }

    private func renderPrefixTargets(
        into out: inout SwiftSource,
        targets: [(dispatcher: Int, target: DispatchTarget)],
        literals: inout LiteralTable
    ) {
        out.line("/// Step 6: the target owning the longest exactly matching prefix. The")
        out.line("/// tests are ordered by descending prefix length, so the first match is")
        out.line("/// the longest one.")
        out.line("static func prefixTarget(_ dispatcher: Int, _ v: [Unicode.Scalar]) -> Int? {")
        out.push()
        out.line("switch dispatcher {")
        for index in bundle.dispatchers.indices {
            var entries: [PrefixEntry] = []
            for (target, entry) in targets.enumerated() where entry.dispatcher == index {
                for prefix in entry.target.acceptedPrefixes {
                    entries.append(PrefixEntry(prefix: prefix, target: target))
                }
            }
            guard !entries.isEmpty else { continue }
            entries.sort {
                $0.length != $1.length ? $0.length > $1.length : precedesByUTF8($0.prefix, $1.prefix)
            }
            out.line("case \(index):")
            out.push()
            for entry in entries {
                out.line(
                    "if PrefixMatch.hasPrefix(v, GeneratedLiterals.\(literals.name(text: entry.prefix))) "
                        + "{ return \(entry.target) }"
                )
            }
            out.line("return nil")
            out.pop()
        }
        out.line("default: return nil")
        out.line("}")
        out.pop()
        out.line("}")
        out.line()
    }

    private func renderImplicitTargets(
        into out: inout SwiftSource,
        targets: [(dispatcher: Int, target: DispatchTarget)]
    ) {
        for (name, predicate) in [
            ("globalTarget", { (target: DispatchTarget) in target.countryCode == nil }),
            ("unprefixedTarget", { (target: DispatchTarget) in target.allowUnprefixedWithoutCountry }),
        ] {
            out.line("static func \(name)(_ dispatcher: Int) -> Int? {")
            out.push()
            out.line("switch dispatcher {")
            for index in bundle.dispatchers.indices {
                let match = targets.indices.first {
                    targets[$0].dispatcher == index && predicate(targets[$0].target)
                }
                if let match { out.line("case \(index): \(match)") }
            }
            out.line("default: nil")
            out.line("}")
            out.pop()
            out.line("}")
            out.line()
        }
    }

    private func renderTargetCountry(
        into out: inout SwiftSource,
        targets: [(dispatcher: Int, target: DispatchTarget)],
        literals: inout LiteralTable
    ) {
        out.line("/// The ISO country of a target, even when its business prefix differs —")
        out.line("/// country `GR` with the canonical VAT prefix `EL`. Absent for GLOBAL.")
        out.line("static func targetCountry(_ target: Int) -> String? {")
        out.push()
        out.line("switch target {")
        for (index, entry) in targets.enumerated() {
            guard let country = entry.target.countryCode else { continue }
            out.line("case \(index): \(SwiftSource.quote(country))")
        }
        out.line("default: nil")
        out.line("}")
        out.pop()
        out.line("}")
        out.line()
    }

    private func renderDefinitionOfTarget(
        into out: inout SwiftSource,
        targets: [(dispatcher: Int, target: DispatchTarget)],
        definitionIndex: [UInt32: Int]
    ) {
        out.line("static func definition(ofTarget target: Int) -> Int {")
        out.push()
        out.line("switch target {")
        for (index, entry) in targets.enumerated() {
            out.line("case \(index): \(definitionIndex[entry.target.identifierDefinitionID] ?? 0)")
        }
        out.line("default: 0")
        out.line("}")
        out.pop()
        out.line("}")
        out.line()
    }

    private func renderDefaultProfile(into out: inout SwiftSource) {
        out.line("/// Applies when, and only when, the caller supplied no profile.")
        out.line("static func defaultProfile(_ definition: Int) -> ValidationProfile {")
        out.push()
        out.line("switch definition {")
        for (index, definition) in bundle.definitions.enumerated() {
            let profile = definition.defaultProfile == "compatible" ? ".compatible" : ".strictCurrent"
            out.line("case \(index): \(profile)")
        }
        out.line("default: .compatible")
        out.line("}")
        out.pop()
        out.line("}")
        out.line()
    }

    private func renderCanonicalize(
        into out: inout SwiftSource,
        targets: [(dispatcher: Int, target: DispatchTarget)],
        definitionIndex: [UInt32: Int],
        literals: inout LiteralTable
    ) {
        out.line("/// Step 10: the canonicalization program of the selected definition, run")
        out.line("/// once on the pre-canonical value. The target supplies what")
        out.line("/// `prepend_country_if_missing` reads.")
        out.line(
            "static func canonicalize(target: Int, _ v: inout [Unicode.Scalar], "
                + "_ profile: ValidationProfile) {"
        )
        out.push()
        out.line("switch target {")
        for (index, entry) in targets.enumerated() {
            guard let definition = definitionIndex[entry.target.identifierDefinitionID] else { continue }
            let program = bundle.definitions[definition].canonicalizationProgram
            let prefixes = literals.name(texts: entry.target.acceptedPrefixes)
            let canonical = literals.name(
                text: entry.target.canonicalPrefix ?? entry.target.countryCode ?? ""
            )
            out.line("case \(index):")
            out.push()
            out.line("GeneratedPrograms.canon\(program)(")
            out.line("    &v,")
            out.line("    CanonicalizationContext(")
            out.line("        profile: profile,")
            out.line("        acceptedPrefixes: GeneratedLiterals.\(prefixes),")
            out.line("        canonicalPrefix: GeneratedLiterals.\(canonical)))")
            out.pop()
        }
        out.line("default: break")
        out.line("}")
        out.pop()
        out.line("}")
        out.line()
    }

    private func renderFormat(into out: inout SwiftSource) {
        out.line("static func format(_ definition: Int, _ c: RuleContext) -> AssertionOutcome {")
        out.push()
        out.line("switch definition {")
        for (index, definition) in bundle.definitions.enumerated() {
            out.line("case \(index): GeneratedPrograms.format\(definition.formatProgram)(c, nil)")
        }
        out.line("default: .pass")
        out.line("}")
        out.pop()
        out.line("}")
        out.line()
    }

    private func renderChecksum(into out: inout SwiftSource) {
        out.line("/// A valid format without a checksum program reports the absence reason")
        out.line("/// the definition declares, which is never a proof of invalidity.")
        out.line("static func checksum(_ definition: Int, _ c: RuleContext) -> ChecksumOutcome {")
        out.push()
        out.line("switch definition {")
        for (index, definition) in bundle.definitions.enumerated() {
            if let program = definition.checksumProgram {
                out.line("case \(index): GeneratedPrograms.checksum\(program)(c, nil)")
            } else {
                let reason = Emission.reasonCase(definition.absentChecksumReason ?? .unsupportedChecksum)
                out.line("case \(index): .unsupported(.\(reason), nil)")
            }
        }
        out.line("default: .unsupportedChecksum")
        out.line("}")
        out.pop()
        out.line("}")
    }
}
