import Foundation
import Testing

@testable import EntIDGenerator

/// `rules.lock` carries the fields `engine.md` section 16 names, in its order.
///
/// The list became normative and machine readable in `2026.08.38`: the contract
/// fences it under ```` ```lock-fields ````. It is read from there rather than
/// repeated here, because a list repeated in an engine is a list that goes
/// stale on the release that changes it — which is the defect section 16 cites.
/// `conformance_jsonl_sha256` existed on one side only, and a release shipped a
/// lock of seven digests where four engines verified eight.
///
/// Order matters as much as membership. Nothing here parses the lock
/// positionally, but the released `rules.lock` and the one this repository
/// writes have to be the same bytes for a synchronization that changes nothing
/// to produce no diff, and that is what fixes the order.
@Suite("rules.lock shape")
struct RulesLockShapeTests {
    static func lockText() throws -> String {
        try String(
            contentsOf: SpecCorpus.root.appending(path: "rules.lock"), encoding: .utf8
        )
    }

    /// The names the contract fences under `lock-fields`, in the order it lists
    /// them.
    static func normativeFields() throws -> [String] {
        let contract = try String(
            contentsOf: SpecCorpus.root.appending(path: "spec").appending(path: "engine.md"),
            encoding: .utf8
        )
        var names: [String] = []
        var inside = false
        for line in contract.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("```lock-fields") {
                inside = true
                continue
            }
            guard inside else { continue }
            if line.hasPrefix("```") { break }
            let name = line.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { names.append(name) }
        }
        return names
    }

    /// The field names `rules.lock` carries, in the order it carries them.
    static func lockFields() throws -> [String] {
        try lockText().split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                let separator = trimmed.firstIndex(of: "=")
            else { return nil }
            return String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
        }
    }

    @Test("The contract still publishes the list")
    func contractPublishesTheList() throws {
        // Without this the comparison below would pass against an empty list,
        // which is how a guard that finds nothing reads exactly like a guard
        // that found no defect.
        let normative = try Self.normativeFields()
        #expect(!normative.isEmpty, "spec/engine.md fences no lock-fields block")
        #expect(normative.first == "rules_version")
        #expect(Set(normative).count == normative.count, "the contract names a field twice")
    }

    @Test("rules.lock carries exactly the normative fields, in the normative order")
    func lockMatchesTheContract() throws {
        let normative = try Self.normativeFields()
        let fields = try Self.lockFields()
        #expect(
            Array(fields.prefix(normative.count)) == normative,
            Comment(rawValue: "lock carries \(fields), contract names \(normative)")
        )
    }

    @Test("An attested release names its identity thirteenth, and nothing follows it")
    func attestationIdentityComesLast() throws {
        let normative = try Self.normativeFields()
        let trailing = Array(try Self.lockFields().dropFirst(normative.count))
        #expect(
            trailing.isEmpty || trailing == ["attestation_identity"],
            Comment(rawValue: "after the normative fields: \(trailing)")
        )

        if trailing.isEmpty {
            // Section 16: a local synchronization does not invent the identity.
            // It leaves a comment where it would have been, so that an absence
            // is read rather than guessed.
            #expect(try Self.lockText().contains("#"), "no identity and nothing said about it")
        } else {
            let identity = try #require(RulesLockFixture.field("attestation_identity"))
            #expect(identity.contains("/.github/workflows/"), Comment(rawValue: identity))
            #expect(identity.contains("@refs/tags/"), Comment(rawValue: identity))
        }
    }
}
