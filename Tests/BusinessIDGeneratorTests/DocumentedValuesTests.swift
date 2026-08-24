import Foundation
import Testing

@testable import BusinessIDGenerator

/// Every identifier printed in a document is synthetic and traceable.
///
/// `engine.md` section 12.2.1 and `DATA_POLICY.md` section 3 separate two
/// demonstrations: a synthetic value proves an **algorithm**, a real one proves
/// that a rule describes what a **register** issues. A README demonstrates an
/// API, so synthetic is correct there — and the only requirement is that the
/// example says so and names the case it came from.
///
/// A sentence saying it is not a guard, which is the lesson of a line in
/// `spec.md` that contradicted `engine.md` for four audits because every
/// mechanical check read the other file. This reads the documents.
///
/// It rests on `spec/businessid-conformance.jsonl`, which `rules.lock` attests
/// since `2026.08.26` under `conformance_jsonl_sha256`. Before that digest
/// existed the file could have drifted with nothing noticing, and a guard built
/// on it would have been worth less than the sentence it replaced.
@Suite("Documented values")
struct DocumentedValuesTests {
    static let documents = [
        "README.md",
        "Examples/BusinessIDConsumer/Sources/BusinessIDConsumer/main.swift",
    ]

    /// A case id as the corpus writes them, quoted in backticks.
    static let caseIDPattern = "`([a-z][a-z0-9]*(?:-[a-z0-9]+)+)`"
    /// An identifier handed to the API in an example.
    static let valuePattern = "value: \"([^\"]*)\""

    struct Corpus {
        let classificationByID: [String: String]
        /// Normalized input to the ids that carry it.
        let idsByNormalizedInput: [String: [String]]
    }

    static func corpus() throws -> Corpus {
        let url = SpecCorpus.root.appending(path: "spec/businessid-conformance.jsonl")
        var classification: [String: String] = [:]
        var byInput: [String: [String]] = [:]
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
            guard
                let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                let id = object["id"] as? String
            else { continue }
            classification[id] = object["dataClassification"] as? String
            if let input = object["input"] as? String {
                byInput[normalized(input), default: []].append(id)
            }
        }
        return Corpus(classificationByID: classification, idsByNormalizedInput: byInput)
    }

    /// Separators and surrounding space are presentation, not identity: a
    /// README shows a printed form on purpose.
    static func normalized(_ value: String) -> String {
        String(value.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
            .uppercased()
    }

    static func matches(_ pattern: String, in text: String) throws -> [String] {
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    static func text(_ document: String) throws -> String {
        try String(contentsOf: SpecCorpus.root.appending(path: document), encoding: .utf8)
    }

    @Test("Every case id a document cites exists in the corpus", arguments: documents)
    func citedCasesExist(_ document: String) throws {
        let corpus = try Self.corpus()
        for cited in try Self.matches(Self.caseIDPattern, in: try Self.text(document)) {
            // Backticks also hold file names, tool names and encodings. Every
            // one of the 666 case ids ends in a group of three to five digits,
            // measured, so that is the shape asserted — `utf-8` and
            // `businessid-gen` are not case ids and must not be looked up.
            let tail = cited.split(separator: "-").last ?? ""
            guard tail.count >= 3, tail.allSatisfy(\.isNumber) else { continue }
            #expect(
                corpus.classificationByID[cited] != nil,
                Comment(rawValue: "\(document) cites \(cited), which the corpus does not carry")
            )
        }
    }

    @Test("Every identifier a document prints is a synthetic corpus value", arguments: documents)
    func printedValuesAreSynthetic(_ document: String) throws {
        let corpus = try Self.corpus()
        for value in try Self.matches(Self.valuePattern, in: try Self.text(document)) {
            let key = Self.normalized(value)
            // Below four characters nothing is an identifier: these are the
            // probes an example uses to show an unknown kind or an empty input.
            guard key.count >= 4 else { continue }

            guard let ids = corpus.idsByNormalizedInput[key] else {
                Issue.record(
                    Comment(
                        rawValue: """
                            \(document) prints \(value.debugDescription), which no conformance case \
                            carries. engine.md section 12.2.1: an example states a synthetic value \
                            and names the case it comes from; a value written from memory is \
                            forbidden everywhere.
                            """
                    )
                )
                continue
            }
            let notSynthetic = ids.filter { corpus.classificationByID[$0] != "synthetic" }
            #expect(
                notSynthetic.isEmpty,
                Comment(rawValue: "\(document) prints a value classified \(notSynthetic)")
            )
        }
    }
}
